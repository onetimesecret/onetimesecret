# lib/onetime/cli/domains/doctor_command.rb
#
# frozen_string_literal: true

# Check and repair custom domain data integrity issues.
#
# Performs the following integrity checks:
#   1. org_id points to an existing organization (CRITICAL)
#   2. display_domain field is not empty (HIGH)
#   3. display_domain_index entries point to valid domains (HIGH)
#   4. Domain with org_id is in org.domains sorted set (MEDIUM)
#   5. org.domains sorted set entries have valid domain objects (MEDIUM)
#   6. verification_state fields are coherent (WARNING)
#   7. txt_validation_value format is valid (LOW)
#   8. domain has no org_id at all — ORPHANED (HIGH, report-only)
#
# Additional checks (opt-in):
#   --familia-audit   Run Familia's generic CustomDomain.health_check, which
#                     covers any declared unique_index, multi_index, and
#                     participates_in relationships automatically. Findings are
#                     appended to the issues array as type :familia_audit.
#
# ## Relationship to `bin/ots domains repair` (SIBLINGS, not overlapping)
#
#   bin/ots domains repair DOMAIN [--org-id X]
#     Targeted, single-domain, ORG-ASSIGNMENT-capable, audited. The only verb
#     that can adopt an orphaned domain into an organization.
#
#   bin/ots domains doctor [--all|--org] [--repair]
#     Broad multi-check scanner including index integrity. Never assigns an org.
#
# Exactly one check (#4, org.domains membership) is shared between them, and
# doctor DELEGATES that repair to Onetime::Operations::Domains::Repair so there
# is a single implementation, a single cross-org guard, and a single
# `domain.repair` AdminAuditEvent. Check #8 reports orphans so a single
# `doctor --all` gives the complete picture, but never fixes them — assigning an
# organization is a human decision (use `domains repair --org-id`).
#
# ## Audit coverage gap (known, deliberate for now)
#
# Doctor's index-housekeeping repairs (display_domain_index entries, stale
# org.domains entries) mutate with an OT.info line but NO AdminAuditEvent. They
# have no single extid-identified target and no colonel surface; extracting an
# Operations::Domains::RepairIndexes op is tracked separately. Only the #4
# membership repair is audited today, by the op it delegates to.
#
# Usage:
#   bin/ots domains doctor secrets.example.com      # Check single domain
#   bin/ots domains doctor --all                    # Scan all domains
#   bin/ots domains doctor --org on8q...            # Scan domains for one org
#   bin/ots domains doctor --all --repair           # Auto-repair issues
#   bin/ots domains doctor --all --json             # JSON output
#   bin/ots domains doctor --all --familia-audit    # Include Familia audit

require 'json'
require 'onetime/operations/domains/repair'

require_relative '../customers/shared'

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

      option :familia_audit,
        type: :boolean,
        default: false,
        desc: 'Additionally run CustomDomain.health_check (Familia generic audit)'

      SEVERITY_ORDER = { critical: 0, high: 1, medium: 2, warning: 3, low: 4 }.freeze

      # Valid 32-char hex pattern for txt_validation_value
      TXT_VALIDATION_PATTERN = /\A[a-f0-9]{32}\z/i

      def call(fqdn: nil, all: false, org: nil, repair: false, json: false, familia_audit: false, **)
        boot_application!

        unless fqdn || all || org
          show_usage
          return
        end

        report = { checked: 0, healthy: 0, issues: [], repaired: [], failed_repairs: [] }

        run_familia_health_check(report) if familia_audit

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
            --familia-audit         Additionally run CustomDomain.health_check
                                    (Familia's generic audit covering declared
                                    indexes and participations; read-only)

          Examples:
            bin/ots domains doctor secrets.example.com
            bin/ots domains doctor --all
            bin/ots domains doctor --org on8q30gih2uxu2cw77jzh7caq07
            bin/ots domains doctor --all --repair
            bin/ots domains doctor --all --familia-audit

          Checks performed:
            1. org_id points to existing organization (CRITICAL)
            2. display_domain field is not empty (HIGH)
            3. display_domain_index entries are valid (HIGH)
            4. Domain is in org.domains sorted set (MEDIUM)
            5. org.domains entries have valid domain objects (MEDIUM)
            6. verification_state is coherent (WARNING)
            7. txt_validation_value format is valid (LOW)
            8. domain has no org_id - ORPHANED (HIGH, report-only)
            +. Familia.health_check (opt-in via --familia-audit)

          Doctor never assigns an organization. To adopt an orphaned domain:
            bin/ots domains repair DOMAIN --org-id ORG
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

        # CHECK: domain has an org at all (report-only)
        check_orphaned_domain(domain, issues)

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
      #
      # ONE check over ONE hash. There used to be a second, byte-identical
      # method (check_display_domain_index_hash_integrity) walking the same
      # Onetime::CustomDomain.display_domain_index with the same predicates,
      # differing only in the reported severity/keys. It reported every stale
      # entry twice, at two severities, and double-counted report[:repaired] —
      # the second delete was a no-op HDEL on an already-removed field, so N
      # real problems surfaced as 2N issues and 2N repairs.
      #
      # display_domain_index is declared `unique_index :display_domain,
      # :display_domain_index` — a single Familia HashKey. Deleting a field uses
      # `.remove`, matching the canonical deletes in
      # lib/onetime/models/custom_domain.rb (rename, and the create rollback).
      # `.remove_field` is only an alias of the same method on HashKey, so the
      # old pair was never doing two different things.
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
          Onetime::CustomDomain.display_domain_index.remove(entry[:fqdn])
          OT.info "[domains doctor] Removed stale display_domain_index[#{entry[:fqdn]}]"
        end

        report[:repaired] << {
          action: :display_domain_index_cleaned,
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

      # CHECK: domain has no org_id at all (ORPHANED)
      #
      # REPORT-ONLY, deliberately. Both check_stale_org_reference and
      # check_org_domains_membership early-return on a blank org_id, so without
      # this check `doctor --all` is blind to every orphan and the operator has
      # to know to also run `domains orphaned`. Doctor still never assigns an
      # organization — that is a human decision carried by the audited
      # `domains repair DOMAIN --org-id ORG` verb.
      def check_orphaned_domain(domain, issues)
        return unless domain.org_id.to_s.strip.empty?

        issues << {
          check: :orphaned_domain,
          severity: :high,
          message: 'domain has no org_id (orphaned)',
          repairable: false,
          repair_action: "Assign an organization: bin/ots domains repair #{domain.display_domain} --org-id <ORG>",
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

        apply_membership_repair(domain, organization, report)
      end

      # Delegate the MUTATION for check #4 to Onetime::Operations::Domains::Repair.
      #
      # Detection stays on organization.domains.member? above: it is O(1), while
      # the op's own check does a load_multi of the whole collection. Do not
      # "unify" the two into the slow path — that makes --all quadratic. The two
      # mechanisms can in principle disagree (member? sees a set entry whose
      # record fails to load; list_domains .compacts it away), so any non
      # :repaired status here is recorded as a failed repair rather than
      # silently swallowed.
      #
      # The op resolves the domain object, enforces the cross-org guard in
      # Organization#add_domain (which RAISES when the domain already belongs to
      # another org — the raw sorted-set add this replaced bypassed it), and
      # records the single `domain.repair` AdminAuditEvent. Doctor must never
      # record its own.
      #
      # Wrapped per domain so one cross-org conflict cannot abort an --all scan.
      def apply_membership_repair(domain, organization, report)
        result = Onetime::Operations::Domains::Repair.new(
          domain: domain,
          actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
          dry_run: false,
        ).call

        unless result.status == :repaired
          return record_failed_repair(domain, organization, report, "repair op returned #{result.status}")
        end

        OT.info "[domains doctor] Added #{domain.display_domain} to org.domains for #{organization.extid} " \
                'via Operations::Domains::Repair'
        report[:repaired] << {
          domain: domain.display_domain,
          action: :added_to_org_domains,
          org: organization.extid,
          repairs_applied: result.repairs_applied,
        }
      rescue StandardError => ex
        record_failed_repair(domain, organization, report, ex.message)
      end

      def record_failed_repair(domain, organization, report, reason)
        OT.le "[domains doctor] Failed to repair #{domain.display_domain} " \
              "for #{organization.extid}: #{reason}"
        report[:failed_repairs] << {
          domain: domain.display_domain,
          action: :added_to_org_domains,
          org: organization.extid,
          error: reason,
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

      # Run Familia's generic CustomDomain.health_check and translate findings
      # into report[:issues] entries. Additive layer — does not replace bespoke
      # checks. Guarded with rescue so a Familia API change cannot crash the
      # doctor command.
      def run_familia_health_check(report)
        audit = Onetime::CustomDomain.health_check

        findings = []
        collect_familia_instance_findings(audit, findings)
        collect_familia_unique_index_findings(audit, findings)
        collect_familia_multi_index_findings(audit, findings)
        collect_familia_participation_findings(audit, findings)

        return if findings.empty?

        report[:issues] << {
          type: :familia_audit,
          model_class: audit.model_class,
          audited_at: audit.audited_at,
          duration: audit.duration,
          issues: findings.sort_by { |i| SEVERITY_ORDER[i[:severity]] },
        }
      rescue StandardError => ex
        report[:issues] << {
          type: :familia_audit,
          issues: [{
            check: :familia_audit_unavailable,
            severity: :warning,
            message: "Familia health_check unavailable: #{ex.message}",
            repairable: false,
          }],
        }
      end

      def collect_familia_instance_findings(audit, findings)
        instances = audit.instances || {}
        phantoms  = Array(instances[:phantoms])
        missing   = Array(instances[:missing])

        unless phantoms.empty?
          findings << {
            check: :familia_instances_phantom,
            severity: :medium,
            message: "#{phantoms.size} phantom instance(s) in timeline but missing from DB",
            phantoms: phantoms.first(10),
            total: phantoms.size,
            repairable: false,
          }
        end

        return if missing.empty?

        findings << {
          check: :familia_instances_missing,
          severity: :high,
          message: "#{missing.size} instance(s) present in DB but absent from timeline",
          missing: missing.first(10),
          total: missing.size,
          repairable: false,
        }
      end

      def collect_familia_unique_index_findings(audit, findings)
        Array(audit.unique_indexes).each do |idx|
          stale   = Array(idx[:stale])
          missing = Array(idx[:missing])

          unless stale.empty?
            findings << {
              check: :familia_unique_index_stale,
              severity: :high,
              index_name: idx[:index_name],
              message: "#{stale.size} stale entries in unique_index #{idx[:index_name]}",
              stale: stale.first(10),
              total: stale.size,
              repairable: false,
            }
          end

          next if missing.empty?

          findings << {
            check: :familia_unique_index_missing,
            severity: :high,
            index_name: idx[:index_name],
            message: "#{missing.size} missing entries in unique_index #{idx[:index_name]}",
            missing: missing.first(10),
            total: missing.size,
            repairable: false,
          }
        end
      end

      def collect_familia_multi_index_findings(audit, findings)
        Array(audit.multi_indexes).each do |idx|
          next if idx[:status] == :not_implemented

          stale    = Array(idx[:stale_members])
          orphaned = Array(idx[:orphaned_keys])

          unless stale.empty?
            findings << {
              check: :familia_multi_index_stale,
              severity: :medium,
              index_name: idx[:index_name],
              message: "#{stale.size} stale members in multi_index #{idx[:index_name]}",
              stale_members: stale.first(10),
              total: stale.size,
              repairable: false,
            }
          end

          next if orphaned.empty?

          findings << {
            check: :familia_multi_index_orphaned,
            severity: :medium,
            index_name: idx[:index_name],
            message: "#{orphaned.size} orphaned keys for multi_index #{idx[:index_name]}",
            orphaned_keys: orphaned.first(10),
            total: orphaned.size,
            repairable: false,
          }
        end
      end

      def collect_familia_participation_findings(audit, findings)
        Array(audit.participations).each do |part|
          stale = Array(part[:stale_members])
          next if stale.empty?

          findings << {
            check: :familia_participation_stale,
            severity: :high,
            collection_name: part[:collection_name],
            message: "#{stale.size} stale members in participation #{part[:collection_name]}",
            stale_members: stale.first(10),
            total: stale.size,
            repairable: false,
          }
        end
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

        if report[:failed_repairs].any?
          puts 'Failed repairs:'
          report[:failed_repairs].each do |failure|
            puts "  #{failure[:domain]} (org #{failure[:org]}): #{failure[:error]}"
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
          when :familia_audit
            puts "Familia Audit (#{issue_group[:model_class] || 'CustomDomain'}):"
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
        # A repair we attempted and did not land is a hard failure, even when
        # every other domain in the scan was fixed. Fail loud, not silently.
        exit 1 if report[:failed_repairs].any?

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
