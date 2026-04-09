# lib/onetime/cli/memberships/doctor_command.rb
#
# frozen_string_literal: true

# Check and repair organization membership data integrity issues.
#
# Performs the following integrity checks:
#   1. organization_objid points to an existing organization (CRITICAL)
#   2. customer_objid points to an existing customer for active memberships (HIGH)
#   3. org.members sorted set entries have backing customer objects (MEDIUM)
#   4. org_customer_lookup index entries point to valid memberships (MEDIUM)
#   5. token_lookup entries are actually pending memberships (MEDIUM)
#   6. org_email_lookup entries are valid (MEDIUM)
#   7. pending_invitations count matches actual pending records (WARNING)
#   8. domain_scope_id points to an existing domain (WARNING)
#
# Usage:
#   bin/ots memberships doctor --all                    # Scan all memberships
#   bin/ots memberships doctor --org on8q...            # Scan memberships for one org
#   bin/ots memberships doctor --all --repair           # Auto-repair issues
#   bin/ots memberships doctor --all --json             # JSON output

require 'json'

module Onetime
  module CLI
    # rubocop:disable Metrics/ClassLength
    class MembershipsDoctorCommand < Command
      desc 'Check organization membership data integrity'

      option :all,
        type: :boolean,
        default: false,
        desc: 'Scan all memberships'

      option :org,
        type: :string,
        default: nil,
        desc: 'Organization extid to check memberships for'

      option :repair,
        type: :boolean,
        default: false,
        desc: 'Auto-repair issues (default: audit only)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'JSON output'

      SEVERITY_ORDER = { critical: 0, high: 1, medium: 2, warning: 3, low: 4 }.freeze

      def call(all: false, org: nil, repair: false, json: false, **)
        boot_application!

        unless all || org
          show_usage
          return
        end

        report = { checked: 0, healthy: 0, issues: [], repaired: [] }

        if org
          organization = load_org(org)
          check_org_memberships(organization, report, repair: repair)
        else
          # Scan all: check indexes first, then per-org memberships
          check_index_integrity(report, repair: repair)
          scan_all_orgs(report, repair: repair)
        end

        output_report(report, json: json, repair: repair)
        exit_with_status(report, repair: repair)
      end

      private

      def show_usage
        puts <<~USAGE
          Usage: bin/ots memberships doctor [options]

          Check organization membership data integrity and optionally repair issues.

          Options:
            --all                   Scan all memberships
            --org EXTID             Check memberships for a specific organization
            --repair                Auto-repair issues (default: audit only)
            --json                  JSON output

          Examples:
            bin/ots memberships doctor --all
            bin/ots memberships doctor --org on8q30gih2uxu2cw77jzh7caq07
            bin/ots memberships doctor --all --repair

          Checks performed:
            1. organization_objid points to existing org (CRITICAL)
            2. customer_objid points to existing customer (HIGH)
            3. org.members entries have backing customers (MEDIUM)
            4. org_customer_lookup index entries are valid (MEDIUM)
            5. token_lookup entries are pending memberships (MEDIUM)
            6. org_email_lookup entries are valid (MEDIUM)
            7. pending_invitations count matches actual (WARNING)
            8. domain_scope_id points to existing domain (WARNING)
        USAGE
      end

      def load_org(extid)
        organization = Onetime::Organization.find_by_extid(extid)
        unless organization
          puts "Organization not found: #{extid}"
          exit 1
        end
        organization
      end

      def scan_all_orgs(report, repair:)
        Onetime::Organization.instances.each do |objid|
          organization = Onetime::Organization.load(objid)
          next unless organization

          check_org_memberships(organization, report, repair: repair)
        end
      end

      def check_org_memberships(organization, report, repair:)
        issues = []

        # CHECK: stale org.members entries
        check_stale_org_members(organization, issues, report, repair: repair)

        # CHECK: pending invitation count accuracy
        check_pending_count(organization, issues, report, repair: repair)

        # CHECK: active memberships for this org
        check_active_memberships(organization, issues, report, repair: repair)

        # CHECK: pending memberships for this org
        check_pending_memberships(organization, issues, report, repair: repair)

        report[:checked] += 1

        if issues.empty?
          report[:healthy] += 1
        else
          report[:issues] << {
            type: :organization,
            org_extid: organization.extid,
            org_objid: organization.objid,
            display_name: organization.display_name,
            issues: issues.sort_by { |i| SEVERITY_ORDER[i[:severity]] },
          }
        end
      end

      # Index-level checks (not scoped to a single org)
      def check_index_integrity(report, repair:)
        issues = []

        check_org_customer_lookup_integrity(issues, report, repair: repair)
        check_token_lookup_integrity(issues, report, repair: repair)
        check_org_email_lookup_integrity(issues, report, repair: repair)

        return if issues.empty?

        report[:issues] << {
          type: :indexes,
          issues: issues.sort_by { |i| SEVERITY_ORDER[i[:severity]] },
        }
      end

      # CHECK: org_customer_lookup entries point to valid memberships
      def check_org_customer_lookup_integrity(issues, report, repair:)
        stale_keys = []

        Onetime::OrganizationMembership.org_customer_lookup.hgetall.each do |key, objid|
          membership = load_membership_by_composite_key(key)

          if membership.nil?
            stale_keys << { key: key, objid: objid, reason: 'membership not found' }
          elsif membership.objid != objid
            stale_keys << { key: key, objid: objid, reason: "objid mismatch (expected #{membership.objid})" }
          end
        end

        return if stale_keys.empty?

        issues << {
          check: :org_customer_lookup_stale,
          severity: :medium,
          message: "#{stale_keys.size} stale org_customer_lookup entries",
          stale_keys: stale_keys.first(10),
          total_stale: stale_keys.size,
          repairable: true,
        }

        return unless repair

        stale_keys.each do |entry|
          Onetime::OrganizationMembership.org_customer_lookup.remove_field(entry[:key])
          OT.info "[memberships doctor] Removed stale org_customer_lookup[#{entry[:key]}]"
        end

        report[:repaired] << {
          action: :org_customer_lookup_cleaned,
          count: stale_keys.size,
        }
      end

      # CHECK: token_lookup entries are actually pending memberships
      def check_token_lookup_integrity(issues, report, repair:)
        phantom_tokens = []

        Onetime::OrganizationMembership.token_lookup.hgetall.each do |token, objid|
          membership = Onetime::OrganizationMembership.load(objid)

          if membership.nil?
            phantom_tokens << { token: token, objid: objid, reason: 'membership not found' }
          elsif !membership.pending?
            phantom_tokens << { token: token, objid: objid, reason: "status is #{membership.status}, not pending" }
          elsif membership.token != token
            phantom_tokens << { token: token, objid: objid, reason: 'token mismatch' }
          end
        end

        return if phantom_tokens.empty?

        issues << {
          check: :token_lookup_phantom,
          severity: :medium,
          message: "#{phantom_tokens.size} phantom token_lookup entries",
          phantom_tokens: phantom_tokens.first(10),
          total_phantom: phantom_tokens.size,
          repairable: true,
        }

        return unless repair

        phantom_tokens.each do |entry|
          Onetime::OrganizationMembership.token_lookup.remove_field(entry[:token])
          OT.info "[memberships doctor] Removed phantom token_lookup[#{entry[:token][0..8]}...]"
        end

        report[:repaired] << {
          action: :token_lookup_cleaned,
          count: phantom_tokens.size,
        }
      end

      # CHECK: org_email_lookup entries are valid
      def check_org_email_lookup_integrity(issues, report, repair:)
        stale_entries = []

        Onetime::OrganizationMembership.org_email_lookup.hgetall.each do |key, objid|
          membership = Onetime::OrganizationMembership.load(objid)

          if membership.nil?
            stale_entries << { key: key, objid: objid, reason: 'membership not found' }
          elsif membership.org_email_key != key
            stale_entries << { key: key, objid: objid, reason: "key mismatch (expected #{membership.org_email_key})" }
          end
        end

        return if stale_entries.empty?

        issues << {
          check: :org_email_lookup_phantom,
          severity: :medium,
          message: "#{stale_entries.size} stale org_email_lookup entries",
          stale_entries: stale_entries.first(10),
          total_stale: stale_entries.size,
          repairable: true,
        }

        return unless repair

        stale_entries.each do |entry|
          Onetime::OrganizationMembership.org_email_lookup.remove_field(entry[:key])
          OT.info "[memberships doctor] Removed stale org_email_lookup[#{entry[:key]}]"
        end

        report[:repaired] << {
          action: :org_email_lookup_cleaned,
          count: stale_entries.size,
        }
      end

      # CHECK: org.members sorted set entries have backing customer objects
      def check_stale_org_members(organization, issues, report, repair:)
        stale_members = []

        organization.members.to_a.each do |customer_objid|
          customer = Onetime::Customer.load(customer_objid)
          stale_members << customer_objid unless customer
        end

        return if stale_members.empty?

        issues << {
          check: :stale_org_members,
          severity: :medium,
          message: "#{stale_members.size} stale member(s) in org.members sorted set",
          stale_ids: stale_members.first(10),
          total_stale: stale_members.size,
          repairable: true,
        }

        return unless repair

        stale_members.each do |customer_objid|
          organization.members.remove(customer_objid)
          # Also clean up any orphan membership record
          cleanup_orphan_membership(organization.objid, customer_objid)
          OT.info "[memberships doctor] Removed stale member #{customer_objid} from #{organization.extid}"
        end

        report[:repaired] << {
          org: organization.extid,
          action: :stale_members_removed,
          count: stale_members.size,
        }
      end

      # CHECK: pending_invitations count matches actual pending records
      def check_pending_count(organization, issues, report, repair:)
        set_count    = organization.pending_invitations.size
        actual_count = 0
        stale_objids = []

        organization.pending_invitations.to_a.each do |objid|
          membership = Onetime::OrganizationMembership.load(objid)
          if membership&.pending?
            actual_count += 1
          else
            stale_objids << objid
          end
        end

        return if stale_objids.empty?

        issues << {
          check: :pending_count_mismatch,
          severity: :warning,
          message: "pending_invitations has #{set_count} entries but only #{actual_count} are actually pending",
          stale_objids: stale_objids.first(10),
          total_stale: stale_objids.size,
          repairable: true,
        }

        return unless repair

        stale_objids.each do |objid|
          organization.pending_invitations.remove(objid)
          OT.info "[memberships doctor] Removed stale pending_invitations entry #{objid} from #{organization.extid}"
        end

        report[:repaired] << {
          org: organization.extid,
          action: :pending_invitations_cleaned,
          count: stale_objids.size,
        }
      end

      # CHECK: active memberships have valid org and customer
      def check_active_memberships(organization, issues, report, repair:)
        organization.members.to_a.each do |customer_objid|
          membership = Onetime::OrganizationMembership.find_by_org_customer(
            organization.objid,
            customer_objid,
          )
          next unless membership

          check_membership_integrity(membership, issues, report, repair: repair)
        end
      end

      # CHECK: pending memberships have valid org
      def check_pending_memberships(organization, issues, report, repair:)
        organization.pending_invitations.to_a.each do |objid|
          membership = Onetime::OrganizationMembership.load(objid)
          next unless membership
          next unless membership.pending?

          check_membership_integrity(membership, issues, report, repair: repair)
        end
      end

      def check_membership_integrity(membership, issues, report, repair:)
        # CHECK: organization exists
        check_orphan_org(membership, issues, report, repair: repair)

        # CHECK: customer exists (for active memberships only)
        check_orphan_customer(membership, issues, report, repair: repair)

        # CHECK: domain_scope_id validity
        check_domain_scope(membership, issues, report, repair: repair)
      end

      # CHECK: organization_objid points to existing organization
      def check_orphan_org(membership, issues, report, repair:)
        return if membership.organization_objid.to_s.empty?

        organization = Onetime::Organization.load(membership.organization_objid)
        return if organization

        issues << {
          check: :orphan_org,
          severity: :critical,
          message: "membership #{membership.objid} references deleted org #{membership.organization_objid}",
          membership_objid: membership.objid,
          org_objid: membership.organization_objid,
          repairable: true,
          repair_action: 'Destroy orphan membership',
        }

        return unless repair

        membership.destroy_with_index_cleanup!
        OT.info "[memberships doctor] Destroyed orphan membership #{membership.objid} (org deleted)"
        report[:repaired] << {
          action: :orphan_membership_destroyed,
          membership_objid: membership.objid,
          reason: :org_deleted,
        }
      end

      # CHECK: customer_objid points to existing customer (active memberships only)
      def check_orphan_customer(membership, issues, report, repair:)
        # Only check active memberships (pending don't have customer_objid yet)
        return unless membership.active?
        return if membership.customer_objid.to_s.empty?

        customer = Onetime::Customer.load(membership.customer_objid)
        return if customer

        issues << {
          check: :orphan_customer,
          severity: :high,
          message: "membership #{membership.objid} references deleted customer #{membership.customer_objid}",
          membership_objid: membership.objid,
          customer_objid: membership.customer_objid,
          repairable: true,
          repair_action: 'Destroy orphan membership',
        }

        return unless repair

        membership.destroy_with_index_cleanup!
        OT.info "[memberships doctor] Destroyed orphan membership #{membership.objid} (customer deleted)"
        report[:repaired] << {
          action: :orphan_membership_destroyed,
          membership_objid: membership.objid,
          reason: :customer_deleted,
        }
      end

      # CHECK: domain_scope_id points to existing domain
      def check_domain_scope(membership, issues, report, repair:)
        return if membership.domain_scope_id.to_s.empty?

        domain = Onetime::CustomDomain.load(membership.domain_scope_id)
        return if domain

        issues << {
          check: :domain_scope_deleted,
          severity: :warning,
          message: "membership #{membership.objid} has domain_scope_id pointing to deleted domain #{membership.domain_scope_id}",
          membership_objid: membership.objid,
          domain_scope_id: membership.domain_scope_id,
          repairable: true,
          repair_action: 'Clear domain_scope_id field',
        }

        return unless repair

        membership.domain_scope_id = nil
        membership.save
        OT.info "[memberships doctor] Cleared domain_scope_id on membership #{membership.objid}"
        report[:repaired] << {
          action: :domain_scope_cleared,
          membership_objid: membership.objid,
        }
      end

      # Helper to load membership by composite key (org_objid:customer_objid)
      def load_membership_by_composite_key(key)
        parts = key.split(':')
        return nil unless parts.size == 2

        org_objid, customer_objid = parts
        Onetime::OrganizationMembership.find_by_org_customer(org_objid, customer_objid)
      end

      # Helper to clean up orphan membership record when removing stale org.members entry
      def cleanup_orphan_membership(org_objid, customer_objid)
        membership = Onetime::OrganizationMembership.find_by_org_customer(org_objid, customer_objid)
        return unless membership

        membership.destroy_with_index_cleanup!
        OT.info "[memberships doctor] Cleaned up orphan membership record for #{org_objid}:#{customer_objid}"
      end

      # Output helpers

      def output_report(report, json:, repair:)
        if json
          output_json(report)
        else
          output_text(report, repair: repair)
        end
      end

      def output_json(report)
        puts JSON.pretty_generate(report)
      end

      def output_text(report, repair:)
        puts 'Membership Health Check'
        puts '=' * 40
        puts

        puts "Organizations checked: #{report[:checked]}"
        puts "Healthy: #{report[:healthy]}"
        puts "With issues: #{report[:issues].size}"
        puts

        if report[:repaired].any?
          puts 'Repaired:'
          report[:repaired].each do |r|
            case r[:action]
            when :stale_members_removed
              puts "  #{r[:org]}: removed #{r[:count]} stale member(s)"
            when :pending_invitations_cleaned
              puts "  #{r[:org]}: cleaned #{r[:count]} stale pending invitation(s)"
            when :orphan_membership_destroyed
              puts "  Destroyed orphan membership #{r[:membership_objid]} (#{r[:reason]})"
            when :domain_scope_cleared
              puts "  Cleared domain_scope_id on #{r[:membership_objid]}"
            when :org_customer_lookup_cleaned
              puts "  Cleaned #{r[:count]} stale org_customer_lookup entries"
            when :token_lookup_cleaned
              puts "  Cleaned #{r[:count]} phantom token_lookup entries"
            when :org_email_lookup_cleaned
              puts "  Cleaned #{r[:count]} stale org_email_lookup entries"
            else
              puts "  #{r[:action]}"
            end
          end
          puts
        end

        return if report[:issues].empty?

        puts 'Issues Found:'
        puts '-' * 40

        report[:issues].each do |issue_group|
          puts
          if issue_group[:type] == :indexes
            puts 'Index Integrity:'
          else
            puts "#{issue_group[:org_extid]} (#{issue_group[:display_name]})"
          end

          issue_group[:issues].each do |issue|
            severity_label = severity_tag(issue[:severity])
            repairable     = issue[:repairable] ? '' : ' [manual fix required]'
            puts "  #{severity_label} #{issue[:message]}#{repairable}"

            puts "             #{issue[:repair_action]}" if issue[:repair_action]
          end
        end

        return if repair

        all_issues     = report[:issues].flat_map { |group| group[:issues] }
        has_repairable = all_issues.any? { |i| i[:repairable] }

        puts
        puts '-' * 40
        if has_repairable
          puts 'To auto-repair repairable issues, run with --repair'
        else
          puts 'All issues require manual intervention.'
        end
      end

      def severity_tag(severity)
        case severity
        when :critical then '[CRITICAL]'
        when :high     then '[HIGH]    '
        when :medium   then '[MEDIUM]  '
        when :warning  then '[WARNING] '
        when :low      then '[LOW]     '
        else                '[UNKNOWN] '
        end
      end

      def exit_with_status(report, repair:)
        return if report[:issues].empty?

        all_issues     = report[:issues].flat_map { |group| group[:issues] }
        has_repairable = all_issues.any? { |i| i[:repairable] }

        if repair
          if report[:repaired].empty?
            if has_repairable
              exit 1
            else
              puts
              puts 'ERROR: --repair specified but no issues are auto-repairable.'
              puts 'Manual intervention required.'
              exit 2
            end
          end
        else
          exit 1
        end
      end
    end
    # rubocop:enable Metrics/ClassLength

    register 'memberships doctor', MembershipsDoctorCommand
  end
end
