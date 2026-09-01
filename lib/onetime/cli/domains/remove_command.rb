# lib/onetime/cli/domains/remove_command.rb
#
# frozen_string_literal: true

# Permanently remove a custom domain — the CLI peer of
# `DELETE /api/colonel/domains/:extid`. Both adapters call the same op
# (Onetime::Operations::Domains::Remove), which owns the teardown, the
# display_domain_index survivor re-assertion (the shadowed-record fix) and the
# single `domain.remove` ColonelAuditEvent. This command owns only CLI concerns.
#
# Usage:
#   bin/ots domains remove example.com                 # preview, confirm, apply
#   bin/ots domains remove example.com --dry-run       # preview only, never mutates
#   bin/ots domains remove example.com --apply         # apply without prompting
#   bin/ots domains remove example.com --yes           # alias of --apply
#   bin/ots domains remove example.com --apply --json  # apply, machine-readable
#
# DOMAIN accepts the display domain (preferred), the domain extid, or its objid.
#
# TWO-PHASE UX (mirrors AdminDomainDetail.vue's dry-run preview -> apply): the
# bare invocation runs the op with dry_run:true first and prints the plan — what
# will be removed, and whether the removal re-asserts a surviving canonical
# record over a drift-produced SHADOW (the crux the op guards). Nothing is
# deleted until the operator confirms at the prompt or passes --apply / --yes.
#
# --dry-run wins over --apply: `--dry-run --apply` still mutates nothing.
#
# CALL COUNT: --dry-run and --apply each make exactly ONE op call. The
# interactive path makes two (plan, then apply). The printed plan is ADVISORY,
# not transactional — state can change between the two calls.
#
# Lives under lib/onetime/cli (not apps/api/domains/cli) so the require of the
# op is unambiguous at load time; registration is identical either way.

require 'json'
require 'onetime/operations/domains/remove'
require_relative '../customers/shared'
require_relative 'shared'

module Onetime
  module CLI
    class DomainsRemoveCommand < Command
      include Customers::Shared
      include Domains::Shared

      # Result statuses that are NOT a command failure.
      OK_STATUSES = [:planned, :removed].freeze

      desc 'Remove (permanently delete) a custom domain'

      argument :domain,
        type: :string,
        required: true,
        desc: 'Domain to remove (display domain, extid, or objid)'

      option :apply,
        type: :boolean,
        default: false,
        aliases: ['-y', '--yes', '-f'],
        desc: 'Apply the removal without prompting'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Show the removal plan without mutating (wins over --apply)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(domain:, apply: false, dry_run: false, json: false, **)
        boot_application!

        target = resolve_domain(domain, json: json)

        if json && !apply && !dry_run
          error_exit('Refusing to remove without --apply in --json mode', json: true)
        end

        result =
          if dry_run
            run_op(target, dry_run: true)
          elsif apply
            run_op(target, dry_run: false)
          else
            confirm_and_apply(target)
          end

        return if result.nil? # operator declined at the prompt

        OT.info "[cli-domains-remove] domain=#{target.display_domain} status=#{result.status} " \
                "dry_run=#{result.dry_run} reasserts=#{result.reasserts_survivor}"

        json ? output_json(result) : output_text(result)
      end

      private

      def run_op(target, dry_run:)
        Onetime::Operations::Domains::Remove.new(
          domain: target,
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: dry_run,
        ).call
      rescue StandardError => ex
        # A blown-up APPLY has already been audited (result: :failure) by the op's
        # AuditedFailure hook; surface it and exit non-zero so it is scriptable.
        error_exit("Removal failed: #{ex.message}", json: false)
      end

      # Two op calls: plan, then apply. Only for the interactive path.
      def confirm_and_apply(target)
        plan = run_op(target, dry_run: true)

        print_plan(plan)
        print "Permanently remove #{plan.display_domain}? [y/N] "
        response = $stdin.gets&.strip&.downcase
        unless response == 'y'
          puts 'Aborted.'
          return nil
        end

        run_op(target, dry_run: false)
      end

      def print_plan(plan)
        puts 'Removal Details:'
        puts "  Domain:               #{plan.display_domain}"
        if plan.org_id.to_s.empty?
          puts '  Organization:         ORPHANED'
        else
          puts "  Organization:         #{plan.org_name || 'N/A'} (#{plan.org_id})"
        end
        if plan.reasserts_survivor
          puts '  Note:                 removing a SHADOW record; the canonical'
          puts '                        display_domain index entry will survive'
        end
        puts
      end

      def output_text(result)
        case result.status
        when :planned
          print_plan(result)
          puts 'Dry run - nothing changed. Re-run with --apply to remove.'
        when :removed
          puts "Removed #{result.display_domain} (#{result.extid})"
          puts '  Re-asserted the surviving canonical index entry' if result.reasserts_survivor
          puts
          puts 'Removal complete'
        end
      end

      def output_json(result)
        puts JSON.pretty_generate(
          status: result.status,
          domain_id: result.domain_id,
          extid: result.extid,
          display_domain: result.display_domain,
          org_id: result.org_id,
          org_name: result.org_name,
          reasserts_survivor: result.reasserts_survivor,
          dry_run: result.dry_run,
        )
        exit 1 unless OK_STATUSES.include?(result.status)
      end
    end

    register 'domains remove', DomainsRemoveCommand
  end
end
