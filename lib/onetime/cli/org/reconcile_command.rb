# lib/onetime/cli/org/reconcile_command.rb
#
# frozen_string_literal: true

# Reconcile an organization's billing + entitlement state.
#
# Usage:
#   bin/ots org reconcile ORG --dry-run          # Which mode would run, no writes
#   bin/ots org reconcile ORG                    # Confirm, then apply
#   bin/ots org reconcile ORG --yes              # Apply, no prompt
#   bin/ots org reconcile ORG --yes --json       # Apply, machine-readable
#
# ORG is an org extid or objid (see Onetime::CLI::Org::Shared#resolve_org).
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
# broken order.
require_relative 'shared'

module Onetime
  module CLI
    class OrgReconcileCommand < Command
      include Org::Shared

      desc 'Reconcile an organization\'s billing + entitlement state'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid or objid'

      option :yes,
        type: :boolean,
        default: false,
        aliases: ['-y', '-f'],
        desc: 'Skip confirmation prompt (required to apply)'
      option :dry_run,
        type: :boolean,
        default: false,
        desc: 'Report the mode that would run; write nothing'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      # --yes and --dry-run are ORTHOGONAL on purpose. --dry-run writes nothing
      # so it needs no confirmation; an applied run always needs --yes (or an
      # interactive 'y'). Deriving one from the other would make --yes do double
      # duty and make a scripted --json call ambiguous.
      def call(org:, yes: false, dry_run: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)

        return unless confirm!(organization, yes: yes, dry_run: dry_run, json: json)

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

      # @return [Boolean] true to proceed
      def confirm!(organization, yes:, dry_run:, json:)
        return true if dry_run || yes

        # Never mutate production org state from a scripted invocation that did
        # not say so.
        error_exit('Refusing to reconcile without --yes in --json mode', json: true) if json

        print "Reconcile #{org_label(organization)}? [y/N] "
        response = $stdin.gets&.strip&.downcase
        return true if response == 'y'

        puts 'Aborted.'
        false
      end

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
        }
        puts JSON.pretty_generate(payload)
        exit 1 unless ok?(result)
      end

      def ok?(result)
        Onetime::Operations::Org::Reconcile::OK_STATUSES.include?(result.status)
      end
    end

    register 'org reconcile', OrgReconcileCommand
  end
end
