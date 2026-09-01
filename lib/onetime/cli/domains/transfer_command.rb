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
#   bin/ots domains transfer example.com --to-org on456   # preview, confirm, apply
#   bin/ots domains transfer example.com --to-org on456 --dry-run
#   bin/ots domains transfer example.com --to-org on456 --yes
#   bin/ots domains transfer example.com --to-org on456 --yes --json
#   bin/ots domains transfer example.com --to-org on456 --from-org on123   # assert source
#   bin/ots domains reassign example.com --to-org on456   # alias
#
# DOMAIN accepts the display domain (preferred), the domain extid, or its objid.
# --to-org / --from-org accept an organization extid (preferred) or objid.
#
# --from-org is an optional OWNERSHIP ASSERTION: when it does not match the
# domain's current owner the op returns :mismatch and mutates nothing.
#
# --dry-run wins over --yes: `--dry-run --yes` still mutates nothing.
#
# Lives under lib/onetime/cli (not apps/api/domains/cli) so the require of the
# op is unambiguous at load time; registration is identical either way.

require 'json'
require 'onetime/operations/domains/transfer'
require_relative '../customers/shared'
require_relative 'shared'

module Onetime
  module CLI
    class DomainsTransferCommand < Command
      include Customers::Shared
      include Domains::Shared

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
      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Show the transfer plan without mutating (wins over --yes)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(domain:, to_org:, from_org: nil, yes: false, dry_run: false, json: false, **)
        boot_application!

        target      = resolve_domain(domain, json: json)
        destination = resolve_org(to_org, json: json)
        source      = from_org.to_s.strip.empty? ? nil : resolve_org(from_org, json: json)

        if json && !yes && !dry_run
          error_exit('Refusing to transfer without --yes in --json mode', json: true)
        end

        result =
          if dry_run
            run_op(target, destination, source, dry_run: true, json: json)
          elsif yes
            run_op(target, destination, source, dry_run: false, json: json)
          else
            confirm_and_apply(target, destination, source, json: json)
          end

        return if result.nil? # operator declined at the prompt

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

      # Two op calls: plan, then apply. Only for the interactive path.
      def confirm_and_apply(target, destination, source, json:)
        plan = run_op(target, destination, source, dry_run: true, json: json)

        # A blocked run (:mismatch) has nothing to confirm; report it verbatim.
        return plan unless plan.status == :planned

        print_plan(plan)
        print "Confirm transfer of #{plan.display_domain}? [y/N] "
        response = $stdin.gets&.strip&.downcase
        unless response == 'y'
          puts 'Aborted.'
          return nil
        end

        run_op(target, destination, source, dry_run: false, json: json)
      end

      def print_plan(plan)
        puts 'Transfer Details:'
        puts "  Domain:               #{plan.display_domain}"
        if plan.from_org_id.to_s.empty?
          puts '  From Organization:    ORPHANED'
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
          print_plan(result)
          puts 'Dry run - nothing changed. Re-run with --yes to apply.'
        when :transferred
          puts "  Removed from #{result.from_org_name || result.from_org_id}" unless result.from_org_id.to_s.empty?
          puts "  Added to #{result.to_org_name || result.to_org_id}"
          puts '  Updated org_id field'
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
        )
        exit 1 unless OK_STATUSES.include?(result.status)
      end
    end

    register 'domains transfer', DomainsTransferCommand
    register 'domains reassign', DomainsTransferCommand
  end
end
