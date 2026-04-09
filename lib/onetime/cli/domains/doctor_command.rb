# lib/onetime/cli/domains/doctor_command.rb
#
# frozen_string_literal: true

# Check and repair custom domain data integrity issues.
#
# Performs the following integrity checks:
#   1. org_id points to an existing organization (CRITICAL)
#   2. display_domain field is not empty (HIGH)
#   3. display_domain_index entries point to valid domains (HIGH)
#   4. display_domains hash entries point to valid domains (MEDIUM)
#   5. Domain with org_id is in org.domains sorted set (MEDIUM)
#   6. org.domains sorted set entries have valid domain objects (MEDIUM)
#   7. verification_state fields are coherent (WARNING)
#   8. txt_validation_value format is valid (LOW)
#
# Usage:
#   bin/ots domains doctor secrets.example.com      # Check single domain
#   bin/ots domains doctor --all                    # Scan all domains
#   bin/ots domains doctor --org on8q...            # Scan domains for one org
#   bin/ots domains doctor --all --repair           # Auto-repair issues
#   bin/ots domains doctor --all --json             # JSON output

require 'json'

module Onetime
  module CLI
    # rubocop:disable Metrics/ClassLength
    class DomainsDoctorCommand < Command
      desc 'Check custom domain data integrity'

      argument :fqdn,
        type: :string,
        required: false,
        desc: 'Domain FQDN to check (e.g., secrets.example.com)'

      option :all,
        type: :boolean,
        default: false,
        desc: 'Scan all domains'

      option :org,
        type: :string,
        default: nil,
        desc: 'Organization extid to check domains for'

      option :repair,
        type: :boolean,
        default: false,
        desc: 'Auto-repair issues (default: audit only)'

      option :json,
        type: :boolean,
        default: false,
        desc: 'JSON output'

      SEVERITY_ORDER = { critical: 0, high: 1, medium: 2, warning: 3, low: 4 }.freeze

      # Valid 32-char hex pattern for txt_validation_value
      TXT_VALIDATION_PATTERN = /\A[a-f0-9]{32}\z/i

      def call(fqdn: nil, all: false, org: nil, repair: false, json: false, **)
        boot_application!

        unless fqdn || all || org
          show_usage
          return
        end

        report = { checked: 0, healthy: 0, issues: [], repaired: [] }

        if fqdn
          domain = load_domain(fqdn)
          check_domain(domain, report, repair: repair)
        elsif org
          organization = load_org(org)
          check_index_integrity(report, repair: repair, scope_org: organization)
          check_org_domains(organization, report, repair: repair)
        else
          check_index_integrity(report, repair: repair)
          scan_all_domains(report, repair: repair)
        end

        output_report(report, json: json, repair: repair)
        exit_with_status(report, repair: repair)
      end

      private

      def show_usage
        puts <<~USAGE
          Usage: bin/ots domains doctor [FQDN] [options]

          Check custom domain data integrity and optionally repair issues.

          Arguments:
            FQDN                    Domain to check (e.g., secrets.example.com)

          Options:
            --all                   Scan all domains
            --org EXTID             Check domains for a specific organization
            --repair                Auto-repair issues (default: audit only)
            --json                  JSON output

          Examples:
            bin/ots domains doctor secrets.example.com
            bin/ots domains doctor --all
            bin/ots domains doctor --org on8q30gih2uxu2cw77jzh7caq07
            bin/ots domains doctor --all --repair

          Checks performed:
            1. org_id points to existing organization (CRITICAL)
            2. display_domain field is not empty (HIGH)
            3. display_domain_index entries are valid (HIGH)
            4. display_domains hash entries are valid (MEDIUM)
            5. Domain is in org.domains sorted set (MEDIUM)
            6. org.domains entries have valid domain objects (MEDIUM)
            7. verification_state is coherent (WARNING)
            8. txt_validation_value format is valid (LOW)
        USAGE
      end

      def load_domain(fqdn)
        domain = Onetime::CustomDomain.load_by_display_domain(fqdn)
        unless domain
          puts "Domain not found: #{fqdn}"
          exit 1
        end
        domain
      end

      def load_org(extid)
        organization = Onetime::Organization.find_by_extid(extid)
        unless organization
          puts "Organization not found: #{extid}"
          exit 1
        end
        organization
      end

      def scan_all_domains(report, repair:)
        Onetime::CustomDomain.instances.each do |objid|
          domain = Onetime::CustomDomain.load(objid)
          next unless domain

          check_domain(domain, report, repair: repair)
        end
      end

      def check_org_domains(organization, report, repair:)
        # Check domains via org.domains sorted set
        check_stale_org_domains(organization, report, repair: repair)

        # Check each domain belonging to this org
        organization.domains.to_a.each do |domain_objid|
          domain = Onetime::CustomDomain.load(domain_objid)
          next unless domain

          check_domain(domain, report, repair: repair)
        end
      end

      def check_domain(domain, report, repair:)
        report[:checked] += 1
        issues            = []

        # CHECK: org_id points to existing organization
        check_stale_org_reference(domain, issues)

        # CHECK: display_domain is not empty
        check_display_domain_missing(domain, issues)

        # CHECK: domain is in org.domains if it has org_id
        check_org_domains_membership(domain, issues, report, repair: repair)

        # CHECK: verification state coherence
        check_verification_coherence(domain, issues)

        # CHECK: txt_validation_value format
        check_txt_validation_format(domain, issues)

        if issues.empty?
          report[:healthy] += 1
        else
          report[:issues] << {
            type: :domain,
            domain_fqdn: domain.display_domain,
            domain_objid: domain.objid,
            domain_extid: domain.extid,
            org_id: domain.org_id,
            issues: issues.sort_by { |i| SEVERITY_ORDER[i[:severity]] },
          }
        end
      end

      # Index-level checks
      def check_index_integrity(report, repair:, scope_org: nil)
        issues = []

        check_display_domain_index_integrity(issues, report, repair: repair)
        check_display_domains_hash_integrity(issues, report, repair: repair)

        if scope_org
          check_stale_org_domains(scope_org, report, repair: repair)
        else
          # Check all orgs for stale domain entries
          check_all_org_domains_integrity(issues, report, repair: repair)
        end

        return if issues.empty?

        report[:issues] << {
          type: :indexes,
          issues: issues.sort_by { |i| SEVERITY_ORDER[i[:severity]] },
        }
      end

      # CHECK: display_domain_index entries point to valid domains
      def check_display_domain_index_integrity(issues, report, repair:)
        stale_entries = []

        Onetime::CustomDomain.display_domain_index.hgetall.each do |fqdn, identifier|
          domain = Onetime::CustomDomain.load(identifier)

          if domain.nil?
            stale_entries << { fqdn: fqdn, identifier: identifier, reason: 'domain not found' }
          elsif domain.display_domain.to_s.downcase != fqdn.downcase
            stale_entries << { fqdn: fqdn, identifier: identifier, reason: "FQDN mismatch (domain has #{domain.display_domain})" }
          end
        end

        return if stale_entries.empty?

        issues << {
          check: :display_domain_index_stale,
          severity: :high,
          message: "#{stale_entries.size} stale display_domain_index entries",
          stale_entries: stale_entries.first(10),
          total_stale: stale_entries.size,
          repairable: true,
        }

        return unless repair

        stale_entries.each do |entry|
          Onetime::CustomDomain.display_domain_index.remove_field(entry[:fqdn])
          OT.info "[domains doctor] Removed stale display_domain_index[#{entry[:fqdn]}]"
        end

        report[:repaired] << {
          action: :display_domain_index_cleaned,
          count: stale_entries.size,
        }
      end

      # CHECK: display_domains hash entries point to valid domains
      def check_display_domains_hash_integrity(issues, report, repair:)
        stale_entries = []

        Onetime::CustomDomain.display_domains.hgetall.each do |fqdn, identifier|
          domain = Onetime::CustomDomain.load(identifier)

          if domain.nil?
            stale_entries << { fqdn: fqdn, identifier: identifier, reason: 'domain not found' }
          elsif domain.display_domain.to_s.downcase != fqdn.downcase
            stale_entries << { fqdn: fqdn, identifier: identifier, reason: "FQDN mismatch (domain has #{domain.display_domain})" }
          end
        end

        return if stale_entries.empty?

        issues << {
          check: :display_domains_hash_stale,
          severity: :medium,
          message: "#{stale_entries.size} stale display_domains hash entries",
          stale_entries: stale_entries.first(10),
          total_stale: stale_entries.size,
          repairable: true,
        }

        return unless repair

        stale_entries.each do |entry|
          Onetime::CustomDomain.display_domains.remove(entry[:fqdn])
          OT.info "[domains doctor] Removed stale display_domains[#{entry[:fqdn]}]"
        end

        report[:repaired] << {
          action: :display_domains_hash_cleaned,
          count: stale_entries.size,
        }
      end

      # CHECK: org.domains sorted set entries have valid domain objects
      def check_stale_org_domains(organization, report, repair:)
        stale_domains = []

        organization.domains.to_a.each do |domain_objid|
          domain = Onetime::CustomDomain.load(domain_objid)

          if domain.nil?
            stale_domains << { objid: domain_objid, reason: 'domain not found' }
          elsif domain.org_id != organization.objid
            stale_domains << { objid: domain_objid, reason: "org_id mismatch (domain has #{domain.org_id})" }
          end
        end

        return if stale_domains.empty?

        report[:issues] << {
          type: :org_domains,
          org_extid: organization.extid,
          org_objid: organization.objid,
          issues: [{
            check: :stale_org_domains,
            severity: :medium,
            message: "#{stale_domains.size} stale entries in org.domains sorted set",
            stale_domains: stale_domains.first(10),
            total_stale: stale_domains.size,
            repairable: true,
          }],
        }

        return unless repair

        stale_domains.each do |entry|
          organization.domains.remove(entry[:objid])

          # Clear the domain's own org_id if it pointed to this org,
          # so loading the domain independently won't yield stale data.
          if entry[:reason] =~ /org_id mismatch/
            domain = Onetime::CustomDomain.load(entry[:objid])
            if domain && domain.org_id == organization.objid
              domain.org_id = nil
              domain.save
              OT.info "[domains doctor] Cleared org_id on domain #{entry[:objid]}"
            end
          end

          OT.info "[domains doctor] Removed stale org.domains entry #{entry[:objid]} from #{organization.extid}"
        end

        report[:repaired] << {
          org: organization.extid,
          action: :stale_org_domains_removed,
          count: stale_domains.size,
        }
      end

      # CHECK all orgs for stale domain entries
      def check_all_org_domains_integrity(_issues, report, repair:)
        Onetime::Organization.instances.each do |objid|
          organization = Onetime::Organization.load(objid)
          next unless organization

          check_stale_org_domains(organization, report, repair: repair)
        end
      end

      # CHECK: org_id points to existing organization
      def check_stale_org_reference(domain, issues)
        return if domain.org_id.to_s.empty?

        organization = Onetime::Organization.load(domain.org_id)
        return if organization

        issues << {
          check: :stale_org_reference,
          severity: :critical,
          message: "org_id '#{domain.org_id}' points to deleted organization",
          repairable: false,
          repair_action: 'Manual decision required: reassign to another org or delete domain',
        }
      end

      # CHECK: display_domain is not empty
      def check_display_domain_missing(domain, issues)
        return unless domain.display_domain.to_s.empty?

        issues << {
          check: :display_domain_missing,
          severity: :high,
          message: 'display_domain field is empty',
          repairable: false,
          repair_action: 'Manual intervention required: cannot infer domain name',
        }
      end

      # CHECK: domain with org_id is in org.domains sorted set
      def check_org_domains_membership(domain, issues, report, repair:)
        return if domain.org_id.to_s.empty?

        organization = Onetime::Organization.load(domain.org_id)
        return unless organization # Already flagged by stale_org_reference

        in_set = organization.domains.member?(domain.objid)
        return if in_set

        issues << {
          check: :org_domains_missing,
          severity: :medium,
          message: "domain has org_id #{domain.org_id} but is not in org.domains sorted set",
          repairable: true,
          repair_action: 'Add domain to org.domains sorted set',
        }

        return unless repair

        organization.domains.add(domain.objid, domain.created.to_i)
        OT.info "[domains doctor] Added #{domain.display_domain} to org.domains for #{organization.extid}"
        report[:repaired] << {
          domain: domain.display_domain,
          action: :added_to_org_domains,
          org: organization.extid,
        }
      end

      # CHECK: verification state coherence
      def check_verification_coherence(domain, issues)
        verified_flag = domain.verified.to_s == 'true'
        has_txt_value = !domain.txt_validation_value.to_s.empty?

        # If verified but no txt_validation_value, this is suspicious but may be legitimate
        # (e.g., verified via alternate method or migrated data)
        return unless verified_flag && !has_txt_value

        issues << {
          check: :verification_incoherent,
          severity: :warning,
          message: "verified='true' but txt_validation_value is empty",
          repairable: false,
          repair_action: 'May be legitimate (migrated data or alternate verification)',
        }
      end

      # CHECK: txt_validation_value format
      def check_txt_validation_format(domain, issues)
        value = domain.txt_validation_value.to_s
        return if value.empty?
        return if value.match?(TXT_VALIDATION_PATTERN)

        issues << {
          check: :txt_format_invalid,
          severity: :low,
          message: "txt_validation_value '#{value[0..15]}...' is not valid 32-char hex",
          repairable: false,
          repair_action: 'Informational only - may need re-verification',
        }
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
        puts 'Domain Health Check'
        puts '=' * 40
        puts

        puts "Domains checked: #{report[:checked]}"
        puts "Healthy: #{report[:healthy]}"
        puts "With issues: #{report[:issues].count { |i| i[:type] == :domain }}"
        puts

        if report[:repaired].any?
          puts 'Repaired:'
          report[:repaired].each do |r|
            case r[:action]
            when :display_domain_index_cleaned
              puts "  Cleaned #{r[:count]} stale display_domain_index entries"
            when :display_domains_hash_cleaned
              puts "  Cleaned #{r[:count]} stale display_domains hash entries"
            when :stale_org_domains_removed
              puts "  #{r[:org]}: removed #{r[:count]} stale org.domains entries"
            when :added_to_org_domains
              puts "  #{r[:domain]}: added to org.domains for #{r[:org]}"
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
          case issue_group[:type]
          when :indexes
            puts 'Index Integrity:'
          when :org_domains
            puts "Organization #{issue_group[:org_extid]} domains:"
          else
            puts "#{issue_group[:domain_fqdn]} (#{issue_group[:domain_extid]})"
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

    register 'domains doctor', DomainsDoctorCommand
  end
end
