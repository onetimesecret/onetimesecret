# lib/onetime/cli/domains/transfer_command.rb
#
# frozen_string_literal: true

# Transfer a custom domain between organizations — the CLI peer of
# `POST /api/colonel/domains/:extid/transfer`. Both adapters call the same op
# (Onetime::Operations::Domains::Transfer), which owns the ownership guard, the
# collection move + owners-index update (with rollback) and the single
# `domain.transfer` ColonelAuditEvent. This command owns only CLI concerns.
#
# Usage:
#   bin/ots domains transfer example.com --to-org on456   # dry run (the default): the plan
#   bin/ots domains transfer example.com --to-org on456 --apply
#   bin/ots domains transfer example.com --to-org on456 --apply --json
#   bin/ots domains transfer example.com --to-org on456 --from-org on123   # assert source
#   bin/ots domains reassign example.com --to-org on456   # alias
#
# DOMAIN accepts the display domain (preferred), the domain extid, or its objid.
# --to-org / --from-org accept an organization extid (preferred) or objid.
#
# --from-org is an optional OWNERSHIP ASSERTION: when it does not match the
# domain's current owner the op returns :mismatch and mutates nothing.
#
# A transfer of an ORPHANED domain (no org_id) is an adoption: the domain's
# ownership verification is reset and a new TXT value issued. The output
# lists the per-domain state the record kept.
#
# DRY RUN IS THE DEFAULT (WriteGate). The bare run prints the plan and writes
# nothing. There is no confirmation prompt: --apply (-y/--yes/-f) is the only
# way to transfer, and --dry-run only states the default. Exactly ONE op call
# per invocation.
#
# Lives under lib/onetime/cli (not apps/api/domains/cli) so the require of the
# op is unambiguous at load time; registration is identical either way.

require 'json'
require 'onetime/operations/domains/transfer'
require_relative '../customers/shared'
require_relative 'shared'
require_relative '../write_gate'

module Onetime
  module CLI
    class DomainsTransferCommand < Command
      include Customers::Shared
      include Domains::Shared
      include WriteGate

      # Result statuses that are NOT a command failure. :mismatch is a refused
      # ownership assertion the operator must act on, so it exits 1.
      OK_STATUSES = [:planned, :transferred].freeze

      desc 'Transfer a custom domain between organizations'

      argument :domain,
        type: :string,
        required: true,
        desc: 'Domain to transfer (display domain, extid, or objid)'

      option :to_org,
        type: :string,
        required: true,
        aliases: ['--org'],
        desc: 'Destination organization extid (or objid)'
      option :from_org,
        type: :string,
        default: nil,
        desc: 'Source org extid (or objid) to ASSERT against the current owner'
      write_gate_options 'Transfer the domain'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(domain:, to_org:, from_org: nil, apply: false, dry_run: false, json: false, **)
        boot_application!

        dry_run     = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        target      = resolve_domain(domain, json: json)
        destination = resolve_org(to_org, json: json)
        source      = from_org.to_s.strip.empty? ? nil : resolve_org(from_org, json: json)

        result = run_op(target, destination, source, dry_run: dry_run, json: json)

        OT.info "[cli-domains-transfer] domain=#{target.display_domain} status=#{result.status} " \
                "to=#{result.to_org_id} dry_run=#{result.dry_run}"

        json ? output_json(result) : output_text(result)
      end

      private

      def run_op(target, destination, source, dry_run:, json:)
        Onetime::Operations::Domains::Transfer.new(
          domain: target,
          to_org: destination,
          from_org: source,
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: dry_run,
        ).call
      rescue StandardError => ex
        # A blown-up APPLY has already been audited (result: :failure) by the op's
        # AuditedFailure hook; surface it and exit non-zero so it is scriptable.
        error_exit("Transfer failed: #{ex.message}", json: json)
      end

      def print_plan(plan)
        puts 'Transfer Details:'
        puts "  Domain:               #{plan.display_domain}"
        if plan.from_org_id.to_s.empty?
          puts '  From Organization:    ORPHANED (adopting it resets its ownership verification)'
        else
          puts "  From Organization:    #{plan.from_org_name || 'N/A'} (#{plan.from_org_id})"
        end
        puts "  To Organization:      #{plan.to_org_name || 'N/A'} (#{plan.to_org_id})"
        puts
      end

      def output_text(result)
        case result.status
        when :mismatch
          error_exit(
            "Domain org_id (#{result.from_org_id}) does not match --from-org. " \
            'Nothing was transferred.',
            json: false,
          )
        when :planned
          dry_run_header
          print_plan(result)
          dry_run_footer('transfer')
        when :transferred
          puts "  Removed from #{result.from_org_name || result.from_org_id}" unless result.from_org_id.to_s.empty?
          puts "  Added to #{result.to_org_name || result.to_org_id}"
          puts '  Updated org_id field'
          result.adoption&.lines&.each { |line| puts "  #{line}" }
          puts
          puts 'Transfer complete'
        end
      end

      def output_json(result)
        puts JSON.pretty_generate(
          status: result.status,
          domain_id: result.domain_id,
          extid: result.extid,
          display_domain: result.display_domain,
          from_org_id: result.from_org_id,
          from_org_name: result.from_org_name,
          to_org_id: result.to_org_id,
          to_org_name: result.to_org_name,
          dry_run: result.dry_run,
          adoption: result.adoption&.to_payload,
        )
        exit 1 unless OK_STATUSES.include?(result.status)
      end
    end

    register 'domains transfer', DomainsTransferCommand
    register 'domains reassign', DomainsTransferCommand
  end
end
