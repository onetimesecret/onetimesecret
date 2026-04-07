# lib/onetime/cli/org/doctor_command.rb
#
# frozen_string_literal: true

# Check and repair organization data integrity issues.
#
# Performs the following integrity checks:
#   1. owner_id points to an existing customer
#   2. owner_id customer is in the members sorted set
#   3. All members in sorted set have backing customer objects
#   4. Membership role:'owner' records match org's owner_id
#   5. Organization has at least one member
#
# Usage:
#   bin/ots org doctor on8q30gih2uxu2cw77jzh7caq07     # Check single org
#   bin/ots org doctor --all                            # Scan all orgs
#   bin/ots org doctor --all --repair                   # Auto-repair issues
#   bin/ots org doctor on8q... --json                   # JSON output

require 'json'

module Onetime
  module CLI
    # rubocop:disable Metrics/ClassLength
    class OrgDoctorCommand < Command
      desc 'Check organization data integrity'

      argument :extid,
        type: :string,
        required: false,
        desc: 'Organization extid (omit for --all scan)'

      option :all,
        type: :boolean,
        default: false,
        desc: 'Scan all organizations'

      option :repair,
        type: :boolean,
        default: false,
        desc: 'Auto-repair issues (default: audit only)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'JSON output'

      # Severity levels for issue reporting
      SEVERITY_ORDER = { critical: 0, high: 1, medium: 2, warning: 3, low: 4 }.freeze

      def call(extid: nil, all: false, repair: false, json: false, **)
        boot_application!

        unless extid || all
          show_usage
          return
        end

        orgs   = all ? scan_all_orgs : [load_org(extid)]
        report = { checked: 0, healthy: 0, issues: [], repaired: [] }

        orgs.each do |org|
          next unless org

          check_org(org, report, repair: repair)
        end

        output_report(report, json: json, repair: repair)

        # Exit with error if issues found
        exit_with_status(report, repair: repair)
      end

      def exit_with_status(report, repair:)
        return if report[:issues].empty?

        # Collect all issues to check repairability
        all_issues     = report[:issues].flat_map { |org| org[:issues] }
        has_repairable = all_issues.any? { |i| i[:repairable] }

        if repair
          # In repair mode: error if nothing was repaired but issues exist
          if report[:repaired].empty?
            if has_repairable
              # Repairable issues exist but repair failed
              exit 1
            else
              # No repairable issues - inform user and exit with error
              puts
              puts 'ERROR: --repair specified but no issues are auto-repairable.'
              puts 'Manual intervention required.'
              exit 2
            end
          end
          # Some repairs succeeded - exit success even if some issues remain
        else
          # Audit mode: exit with error code to indicate issues found
          exit 1
        end
      end

      private

      def show_usage
        puts <<~USAGE
          Usage: bin/ots org doctor [EXTID] [options]

          Check organization data integrity and optionally repair issues.

          Arguments:
            EXTID                   Organization extid to check (optional if --all)

          Options:
            --all                   Scan all organizations
            --repair                Auto-repair issues (default: audit only)
            --json                  JSON output

          Examples:
            bin/ots org doctor on8q30gih2uxu2cw77jzh7caq07
            bin/ots org doctor --all
            bin/ots org doctor --all --repair

          Checks performed:
            1. owner_id points to existing customer (CRITICAL)
            2. owner_id customer is in members set (HIGH)
            3. All members have backing customer objects (MEDIUM)
            4. Membership role:'owner' matches owner_id (WARNING)
            5. Organization has at least one member (WARNING)
        USAGE
      end

      def load_org(extid)
        org = Onetime::Organization.find_by_extid(extid)
        unless org
          puts "Organization not found: #{extid}"
          exit 1
        end
        org
      end

      def scan_all_orgs
        orgs = []
        Onetime::Organization.instances.each do |objid|
          org = Onetime::Organization.load(objid)
          orgs << org if org
        end
        orgs
      end

      def check_org(org, report, repair:)
        report[:checked] += 1
        issues            = []

        # CHECK 1: owner_id -> existing customer
        check_owner_exists(org, issues, report, repair: repair)

        # CHECK 2: owner in members set (only if owner exists)
        check_owner_in_members(org, issues, report, repair: repair)

        # CHECK 3: members have backing objects
        check_members_exist(org, issues, report, repair: repair)

        # CHECK 4: membership role sync
        check_membership_role_sync(org, issues)

        # CHECK 5: has members
        check_has_members(org, issues)

        if issues.empty?
          report[:healthy] += 1
        else
          report[:issues] << {
            org_extid: org.extid,
            org_objid: org.objid,
            display_name: org.display_name,
            issues: issues.sort_by { |i| SEVERITY_ORDER[i[:severity]] },
          }
        end
      end

      def check_owner_exists(org, issues, report, repair:)
        return if org.owner_id.to_s.empty?

        owner_customer = Onetime::Customer.load(org.owner_id)
        return if owner_customer

        # Find potential repair candidate (member with role:'owner')
        candidate = find_owner_candidate(org)

        issue = {
          check: :owner_exists,
          severity: :critical,
          message: "owner_id '#{org.owner_id}' points to deleted customer",
          repairable: !candidate.nil?,
        }

        if candidate
          issue[:repair_action] = "Will promote #{candidate[:extid]} (#{candidate[:email]}) as new owner"
          issue[:candidate]     = candidate
        else
          issue[:repair_action] = 'No eligible candidate found (no member with role:owner)'
        end

        issues << issue

        return unless repair

        if candidate
          # Actually perform the promotion
          promoted = promote_owner_from_membership(org)
          if promoted
            report[:repaired] << {
              org: org.extid,
              action: :owner_promoted,
              new_owner_custid: promoted[:custid],
              new_owner_extid: promoted[:extid],
            }
          end
        else
          OT.info "[org doctor] Could not auto-repair #{org.extid}: no eligible owner candidate"
        end
      end

      def check_owner_in_members(org, issues, report, repair:)
        return if org.owner_id.to_s.empty?

        owner_customer = Onetime::Customer.load(org.owner_id)
        return unless owner_customer # Already flagged by check_owner_exists
        return if org.member?(owner_customer)

        issues << {
          check: :owner_in_members,
          severity: :high,
          message: "owner '#{org.owner_id}' not in members set",
          repairable: true,
        }

        return unless repair

        # Add owner to members set with proper membership record
        org.add_members_instance(owner_customer)
        ensure_membership_record(org, owner_customer, role: 'owner')
        report[:repaired] << { org: org.extid, action: :owner_added_to_members }
      end

      def check_members_exist(org, issues, report, repair:)
        stale_members = find_stale_members(org)
        return if stale_members.empty?

        issues << {
          check: :members_exist,
          severity: :medium,
          message: "#{stale_members.size} stale member(s) in set",
          stale_ids: stale_members,
          repairable: true,
        }

        return unless repair

        remove_stale_members(org, stale_members)
        report[:repaired] << {
          org: org.extid,
          action: :stale_members_removed,
          count: stale_members.size,
        }
      end

      def check_membership_role_sync(org, issues)
        role_mismatches = find_role_mismatches(org)
        return if role_mismatches.empty?

        issues << {
          check: :membership_role_sync,
          severity: :warning,
          message: "#{role_mismatches.size} membership(s) with role:'owner' but custid != owner_id",
          mismatches: role_mismatches,
          repairable: false, # requires manual decision
        }
      end

      def check_has_members(org, issues)
        return if org.member_count.positive?

        issues << {
          check: :has_members,
          severity: :warning,
          message: 'organization has no members',
          repairable: false,
        }
      end

      # Repair helpers

      def find_owner_candidate(org)
        # Find a member with role:'owner' who could be promoted (read-only check)
        org.members.to_a.each do |member_id|
          membership = find_membership(org.objid, member_id)
          next unless membership
          next unless membership.role == 'owner'

          customer = Onetime::Customer.load(member_id)
          next unless customer # skip if this owner candidate is also deleted

          return {
            custid: customer.custid,
            extid: customer.extid,
            email: customer.obscure_email,
          }
        end
        nil
      end

      def promote_owner_from_membership(org)
        # Find a member with role:'owner' in their membership record
        org.members.to_a.each do |member_id|
          membership = find_membership(org.objid, member_id)
          next unless membership
          next unless membership.role == 'owner'

          customer = Onetime::Customer.load(member_id)
          next unless customer # skip if this owner candidate is also deleted

          # Update org.owner_id
          org.owner_id = customer.custid
          unless org.save
            OT.le "[org doctor] Failed to save org #{org.extid} after owner promotion"
            next
          end
          OT.info "[org doctor] Promoted #{customer.extid} as owner of #{org.extid}"
          return { custid: customer.custid, extid: customer.extid }
        end
        nil
      end

      def ensure_membership_record(org, customer, role:)
        membership = Onetime::OrganizationMembership.ensure_membership(org, customer, role: role)
        OT.info "[org doctor] Ensured membership for #{customer.extid} in #{org.extid} with role:#{role}"
        membership
      end

      def find_stale_members(org)
        stale = []
        org.members.to_a.each do |member_id|
          exists = Familia.dbclient.exists?("customer:#{member_id}:object")
          stale << member_id unless exists
        end
        stale
      end

      def remove_stale_members(org, stale_ids)
        redis = Familia.dbclient
        stale_ids.each do |member_id|
          # Remove from sorted set using raw Redis ZREM (we have string ID, not Customer object)
          redis.zrem(org.members.dbkey, member_id)

          # Clean up orphan membership record if exists
          membership_key = membership_key(org.objid, member_id)
          redis.del(membership_key)

          OT.info "[org doctor] Removed stale member #{member_id} from #{org.extid}"
        end
      end

      def find_role_mismatches(org)
        mismatches = []
        org.members.to_a.each do |member_id|
          membership = find_membership(org.objid, member_id)
          next unless membership
          next unless membership.role == 'owner'
          next if member_id == org.owner_id # correct: this IS the owner

          mismatches << {
            member_id: member_id,
            membership_role: 'owner',
            org_owner_id: org.owner_id,
          }
        end
        mismatches
      end

      def find_membership(org_objid, customer_objid)
        Onetime::OrganizationMembership.find_by_org_customer(org_objid, customer_objid)
      end

      # Build the Redis key for a membership record (used for cleanup of orphans)
      def membership_key(org_objid, customer_objid)
        "org_membership:organization:#{org_objid}:customer:#{customer_objid}:org_membership:object"
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

      # rubocop:disable Metrics/PerceivedComplexity
      def output_text(report, repair:)
        puts 'Organization Health Check'
        puts '=' * 40
        puts

        puts "Checked: #{report[:checked]}"
        puts "Healthy: #{report[:healthy]}"
        puts "Issues:  #{report[:issues].size}"
        puts

        if report[:repaired].any?
          puts 'Repaired:'
          report[:repaired].each do |r|
            case r[:action]
            when :owner_promoted
              puts "  #{r[:org]}: promoted #{r[:new_owner_extid]} as new owner"
            when :owner_added_to_members
              puts "  #{r[:org]}: added owner to members set"
            when :stale_members_removed
              puts "  #{r[:org]}: removed #{r[:count]} stale member(s)"
            else
              puts "  #{r[:org]}: #{r[:action]}"
            end
          end
          puts
        end

        return if report[:issues].empty?

        puts 'Issues Found:'
        puts '-' * 40

        report[:issues].each do |org_issues|
          puts
          puts "#{org_issues[:org_extid]} (#{org_issues[:display_name]})"

          org_issues[:issues].each do |issue|
            severity_label = severity_tag(issue[:severity])
            repairable     = issue[:repairable] ? '' : ' [manual fix required]'
            puts "  #{severity_label} #{issue[:message]}#{repairable}"

            # Show repair action hint for repairable issues
            if issue[:repair_action]
              puts "             #{issue[:repair_action]}"
            end

            # Show additional details for certain issues
            if issue[:stale_ids]
              issue[:stale_ids].first(5).each do |id|
                puts "    - #{id}"
              end
              remaining = issue[:stale_ids].size - 5
              puts "    ... and #{remaining} more" if remaining.positive?
            end

            next unless issue[:mismatches]

            issue[:mismatches].first(3).each do |m|
              puts "    - member #{m[:member_id]} has role:'owner' but owner_id=#{m[:org_owner_id]}"
            end
            remaining = issue[:mismatches].size - 3
            puts "    ... and #{remaining} more" if remaining.positive?
          end
        end

        return if repair

        # Only suggest --repair if there are repairable issues
        all_issues     = report[:issues].flat_map { |org| org[:issues] }
        has_repairable = all_issues.any? { |i| i[:repairable] }

        puts
        puts '-' * 40
        if has_repairable
          puts 'To auto-repair repairable issues, run with --repair'
        else
          puts 'All issues require manual intervention.'
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

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
    end
    # rubocop:enable Metrics/ClassLength

    register 'org doctor', OrgDoctorCommand
  end
end
