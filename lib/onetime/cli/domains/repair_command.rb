# lib/onetime/cli/domains/repair_command.rb
#
# frozen_string_literal: true

# Repair a custom domain's organization relationship — the CLI peer of
# `POST /api/colonel/domains/:extid/repair`. Both adapters call the same op
# (Onetime::Operations::Domains::Repair), which owns the mutation and the
# single `domain.repair` AdminAuditEvent. This command owns only CLI concerns.
#
# Usage:
#   bin/ots domains repair example.com                    # plan, confirm, apply
#   bin/ots domains repair example.com --dry-run          # plan only, never mutates
#   bin/ots domains repair example.com --yes              # apply without prompting
#   bin/ots domains repair example.com --yes --json       # apply, machine-readable
#   bin/ots domains repair example.com --org-id on123abc  # adopt an ORPHANED domain
#
# DOMAIN accepts the display domain (preferred), the domain extid, or its objid.
#
# --org-id accepts an organization extid (preferred) or objid and is ONLY
# meaningful for an ORPHANED domain (blank org_id). Passed against a domain that
# already has an org it is a hard error: the op ignores it there, and silently
# ignoring an explicit flag is how an operator ends up believing a reassignment
# happened. Reassignment is `domains transfer`, a separate audited verb.
#
# --dry-run wins over --yes: `--dry-run --yes` still mutates nothing.
#
# CALL COUNT: --dry-run and --yes each make exactly ONE op call. The interactive
# path makes two (plan, then apply). The printed plan is ADVISORY, not
# transactional — state can change between the two calls.
#
# `--force` was renamed to `--yes` (`-y` / `-f` aliases). This is a deliberate
# break; see the changelog.
#
# Lives under lib/onetime/cli (not apps/api/domains/cli) so the require of the
# op is unambiguous at load time; registration is identical either way.

require 'json'
require 'onetime/operations/domains/repair'
# Customers::Shared / Domains::Shared must exist before the `include`s below.
# Required here (not only from the lib/onetime/cli.rb manifest) so this file
# cannot be loaded in a broken order.
require_relative '../customers/shared'
require_relative 'shared'

module Onetime
  module CLI
    class DomainsRepairCommand < Command
      include Customers::Shared
      include Domains::Shared

      # Result statuses that are NOT a command failure. :needs_org and
      # :org_not_found are blocked states the operator must act on, so they
      # exit 1 — the incumbent command exited 0 and was unscriptable.
      OK_STATUSES = [:repaired, :no_issues, :planned].freeze

      desc 'Fix domain relationship issues'

      argument :domain,
        type: :string,
        required: true,
        desc: 'Domain to repair (display domain, extid, or objid)'

      option :org_id,
        type: :string,
        default: nil,
        desc: 'Organization extid (or objid) to assign when the domain is ORPHANED'
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Show the repair plan without mutating (wins over --yes)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(domain:, org_id: nil, yes: false, dry_run: false, json: false, **)
        boot_application!

        target = resolve_domain(domain, json: json)

        # Resolve --org-id BEFORE prompting so bad input fails fast. The
        # incumbent passed silent: true here, so an unresolvable org became an
        # invisible nil and the command then told the operator to supply the
        # very flag they had just supplied.
        org = org_id.to_s.strip.empty? ? nil : resolve_org(org_id, json: json)

        reject_reassignment!(target, json: json) if org

        if json && !yes && !dry_run
          error_exit('Refusing to repair without --yes in --json mode', json: true)
        end

        unless json
          puts "Checking domain: #{target.display_domain}"
          puts
        end

        result =
          if dry_run
            run_op(target, org, dry_run: true)
          elsif yes
            run_op(target, org, dry_run: false)
          else
            confirm_and_apply(target, org)
          end

        return if result.nil? # operator declined at the prompt

        OT.info "[cli-domains-repair] domain=#{target.display_domain} status=#{result.status} " \
                "dry_run=#{result.dry_run} issues=#{result.issues.size}"

        json ? output_json(result) : output_text(target, result)
      end

      private

      def run_op(target, org, dry_run:)
        Onetime::Operations::Domains::Repair.new(
          domain: target,
          org: org,
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: dry_run,
        ).call
      end

      # Two op calls: plan, then apply. Only for the interactive path.
      def confirm_and_apply(target, org)
        plan = run_op(target, org, dry_run: true)

        # Blocked (:needs_org / :org_not_found) or clean (:no_issues): there is
        # nothing to confirm, so report the plan verbatim and skip the apply.
        return plan unless plan.status == :planned

        puts 'Issues Found:'
        plan.issues.each_with_index { |issue, idx| puts "  #{idx + 1}. #{issue}" }
        puts
        print "Apply #{plan.issues.size} repair(s) to #{target.display_domain}? [y/N] "
        response = $stdin.gets&.strip&.downcase
        unless response == 'y'
          puts 'Aborted.'
          return nil
        end

        run_op(target, org, dry_run: false)
      end

      # --org-id only adopts an ORPHANED domain. Anything else is a transfer.
      def reject_reassignment!(target, json:)
        return if target.org_id.to_s.strip.empty?

        error_exit(
          "--org-id cannot reassign #{target.display_domain}: it already belongs to " \
          "#{target.org_id}. Use: bin/ots domains transfer #{target.display_domain} --to-org <ORG>",
          json: json,
        )
      end

      def output_text(target, result)
        case result.status
        when :no_issues
          puts 'No issues found - domain relationships are consistent'
        when :planned
          puts 'Issues Found:'
          result.issues.each_with_index { |issue, idx| puts "  #{idx + 1}. #{issue}" }
          puts
          puts 'Dry run - nothing changed. Re-run with --yes to apply.'
        when :repaired
          puts 'Applying repairs:'
          result.repairs_applied.each { |applied| puts "  #{applied}" }
          puts
          puts 'Repair complete'
        when :needs_org
          error_exit(
            'Domain is orphaned (no org_id). Assign one with: ' \
            "bin/ots domains repair #{target.display_domain} --org-id <ORG>",
            json: false,
          )
        when :org_not_found
          error_exit(
            "org_id is #{target.org_id} but that organization does not exist. Reassign with: " \
            "bin/ots domains transfer #{target.display_domain} --to-org <ORG>",
            json: false,
          )
        end
      end

      def output_json(result)
        puts JSON.pretty_generate(
          status: result.status,
          domain_id: result.domain_id,
          extid: result.extid,
          display_domain: result.display_domain,
          issues: result.issues,
          repairs_applied: result.repairs_applied,
          dry_run: result.dry_run,
        )
        exit 1 unless OK_STATUSES.include?(result.status)
      end
    end

    register 'domains repair', DomainsRepairCommand
  end
end
