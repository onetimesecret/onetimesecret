# lib/onetime/cli/domains/remove_command.rb
#
# frozen_string_literal: true

# Permanently remove a custom domain — the CLI peer of
# `DELETE /api/colonel/domains/:extid`. Both adapters call the same op
# (Onetime::Operations::Domains::Remove), which owns the teardown and the
# single `domain.remove` ColonelAuditEvent. This command owns only CLI concerns.
#
# Usage:
#   bin/ots domains remove example.com                 # dry run (the default): the plan
#   bin/ots domains remove example.com --apply         # remove
#   bin/ots domains remove example.com --yes           # alias of --apply
#   bin/ots domains remove example.com --apply --json  # remove, machine-readable
#
# DOMAIN accepts the display domain (preferred), the domain extid, or its objid.
#
# DRY RUN IS THE DEFAULT (WriteGate). The bare run prints the plan — what will
# be removed — and writes nothing. There is no confirmation prompt: --apply
# (-y/--yes/-f) is the only way to remove, and --dry-run only states the
# default. Exactly ONE op call per invocation. The printed plan is ADVISORY,
# not transactional — state can change between a dry run and the apply.
#
# SENDER CLEANUP: an apply reports the teardown's remote sender identity
# outcome (Remove::Result#sender_cleanup). A :failed cleanup does not undo the
# removal, but it exits 1: the record is gone, the provider identity may
# remain, and a rerun cannot retry the cleanup.
#
# Lives under lib/onetime/cli (not apps/api/domains/cli) so the require of the
# op is unambiguous at load time; registration is identical either way.

require 'json'
require 'onetime/operations/domains/remove'
require_relative '../customers/shared'
require_relative 'shared'
require_relative '../write_gate'

module Onetime
  module CLI
    class DomainsRemoveCommand < Command
      include Customers::Shared
      include Domains::Shared
      include WriteGate

      # Result statuses that are NOT a command failure.
      OK_STATUSES = [:planned, :removed].freeze

      desc 'Remove (permanently delete) a custom domain'

      argument :domain,
        type: :string,
        required: true,
        desc: 'Domain to remove (display domain, extid, or objid)'

      write_gate_options 'Remove the domain'
      # OPTIONAL operator-supplied why (#4338), recorded in the audit detail
      # of the event this command's op writes. Same flag, same wording and same
      # blank-means-absent handling as every other destructive CLI verb.
      option :reason,
        type: :string,
        default: nil,
        desc: 'Operator-supplied reason (recorded in the admin audit trail)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(domain:, apply: false, dry_run: false, reason: nil, json: false, **)
        boot_application!

        dry_run = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        target  = resolve_domain(domain, json: json)

        result = run_op(target, dry_run: dry_run, reason: reason, json: json)

        OT.info "[cli-domains-remove] domain=#{target.display_domain} status=#{result.status} " \
                "dry_run=#{result.dry_run} sender_cleanup=#{result.sender_cleanup}"

        json ? output_json(result) : output_text(result)
      end

      private

      def run_op(target, dry_run:, reason:, json:)
        Onetime::Operations::Domains::Remove.new(
          domain: target,
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: dry_run,
          reason: reason,
        ).call
      rescue StandardError => ex
        # A blown-up APPLY has already been audited (result: :failure) by the op's
        # AuditedFailure hook; surface it and exit non-zero so it is scriptable.
        error_exit("Removal failed: #{ex.message}", json: json)
      end

      def print_plan(plan)
        puts 'Removal Details:'
        puts "  Domain:               #{plan.display_domain}"
        if plan.org_id.to_s.empty?
          puts '  Organization:         ORPHANED'
        else
          puts "  Organization:         #{plan.org_name || 'N/A'} (#{plan.org_id})"
        end
        puts
      end

      def output_text(result)
        case result.status
        when :planned
          dry_run_header
          print_plan(result)
          dry_run_footer('remove')
        when :removed
          puts "Removed #{result.display_domain} (#{result.extid})"
          puts "  Sender identity:      #{result.sender_cleanup}"
          puts
          if sender_cleanup_failed?(result)
            puts 'Removal incomplete: the domain record was removed, but the provider sender identity may remain.'
            puts "  The 'Sender domain deletion failed' log names the provider and the error."
            puts '  A rerun cannot retry this cleanup; remove the identity at the provider.'
            exit 1
          end
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
          dry_run: result.dry_run,
          sender_cleanup: result.sender_cleanup,
        )
        exit 1 unless OK_STATUSES.include?(result.status)
        exit 1 if sender_cleanup_failed?(result)
      end

      def sender_cleanup_failed?(result)
        result.sender_cleanup == :failed
      end
    end

    register 'domains remove', DomainsRemoveCommand
  end
end
