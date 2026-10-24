# lib/onetime/cli/org/reconcile_command.rb
#
# frozen_string_literal: true

# Reconcile an organization's billing + entitlement state.
#
# Usage:
#   bin/ots org reconcile ORG                    # Dry run (the default): which mode would run
#   bin/ots org reconcile ORG --apply            # Apply
#   bin/ots org reconcile ORG --apply --json     # Apply, machine-readable
#
# ORG is an org extid or objid (see Onetime::CLI::Org::Shared#resolve_org).
#
# DRY RUN IS THE DEFAULT. Nothing is written without --apply (-y/--yes/-f are
# aliases). There is no confirmation prompt; --dry-run only says so explicitly.
#
# The mutation + the admin audit event are performed by the shared
# Onetime::Operations::Org::Reconcile op (the single implementation; the colonel
# ReconcileOrganization Logic class is the other adapter). This command owns only
# CLI concerns. The CLI runs outside the app autoloaders, so require the op
# explicitly.
require 'json'
require 'onetime/operations/org/reconcile'
# Org::Shared must exist before `include Org::Shared` below. Required here (not
# only from the lib/onetime/cli.rb manifest) so this file cannot be loaded in a
# broken order. Customers::Shared is referenced by constant only (CLI_ACTOR), so
# it is required but NOT included — including it would drag its resolver methods
# into a command that resolves orgs, not customers.
require_relative 'shared'
require_relative '../customers/shared'

module Onetime
  module CLI
    class OrgReconcileCommand < Command
      include Org::Shared

      # The dry-run statuses that an --apply run would act on.
      PLANNED_STATUSES = [:planned, :would_materialize].freeze

      desc 'Reconcile an organization\'s billing + entitlement state'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid or objid'

      option :apply,
        type: :boolean,
        default: false,
        aliases: ['-y', '--yes', '-f'],
        desc: 'Reconcile (default: dry run, report the mode that would run)'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Preview only (the default; contradicts --apply)'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, apply: false, dry_run: false, json: false, **)
        boot_application!

        dry_run      = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        organization = resolve_org(org, json: json)

        result = Onetime::Operations::Org::Reconcile.new(
          org: organization,
          # Never fabricate a Customer for the shell (ADR-023) — the audit trail
          # records the shared CLI sentinel.
          actor: Customers::Shared::CLI_ACTOR,
          dry_run: dry_run,
        ).call

        OT.info "[cli-org-reconcile] org=#{organization.extid} status=#{result.status} " \
                "mode=#{result.mode} dry_run=#{result.dry_run}"

        json ? output_json(result) : output_text(result)
      end

      private

      def output_text(result)
        if result.status == :stripe_error
          error_exit("Stripe error: #{result.reason}", json: false)
        end

        puts 'DRY RUN — nothing was written' if result.dry_run
        puts "Organization: #{result.org_id}"
        puts "Mode:         #{result.mode}"
        puts "Status:       #{result.status}"
        puts "Reason:       #{result.reason}" if result.reason
        puts
        print_diff(result)
        print_cascade(result)
        puts "\nRe-run with --apply to reconcile." if PLANNED_STATUSES.include?(result.status)

        exit 1 unless ok?(result)
      end

      def print_diff(result)
        after = result.after
        puts format('%-26s %-22s %s', 'Field', 'Before', after ? 'After' : 'After (not applied)')
        snapshot_fields.each do |key|
          puts format('%-26s %-22s %s', key, render(result.before[key]), after ? render(after[key]) : '-')
        end
      end

      def snapshot_fields
        [:planid, :subscription_status, :subscription_period_end, :materialized_count]
      end

      # Membership-cascade outcome (#3907 item 3): a partial cascade must be
      # visible without log access. `memberships` is nil when the cascade did
      # not run (dry run, skip, stripe_error) and on an applied run whose
      # cascade raised — the op's logs carry that case, so print nothing rather
      # than fabricate counts. failed_ids are membership OBJIDs, the identifier
      # `bin/ots memberships doctor` follow-up works in.
      def print_cascade(result)
        cascade = result.memberships
        return unless cascade

        puts
        line = "Memberships:  #{cascade[:success]}/#{cascade[:total]} re-materialized"
        if cascade[:failed].to_i.positive?
          line += " — #{cascade[:failed]} FAILED: #{cascade[:failed_ids].join(', ')}"
        end
        puts line
      end

      def render(value)
        value.to_s.empty? ? '(none)' : value.to_s
      end

      def output_json(result)
        payload = {
          status: result.status,
          org_id: result.org_id,
          mode: result.mode,
          reason: result.reason,
          dry_run: result.dry_run,
          before: result.before,
          after: result.after,
          memberships: result.memberships,
        }
        puts JSON.pretty_generate(payload)
        exit 1 unless ok?(result)
      end

      def ok?(result)
        Onetime::Operations::Org::Reconcile::OK_STATUSES.include?(result.status)
      end
    end

    register 'organizations reconcile', OrgReconcileCommand
  end
end
