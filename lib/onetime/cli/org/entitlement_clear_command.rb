# lib/onetime/cli/org/entitlement_clear_command.rb
#
# frozen_string_literal: true

# Wipe ALL operator entitlement overrides on an organization.
#
# Usage:
#   bin/ots org entitlement clear ORG             # Dry run (the default): project the result
#   bin/ots org entitlement clear ORG --apply     # Apply
#   bin/ots org entitlement clear ORG --apply --json
#
# ORG is an org extid or objid (see Onetime::CLI::Org::Shared#resolve_org).
#
# This is THE destructive verb of the group: it empties `entitlements_grants`
# AND `entitlements_revokes`, then re-reconciles the org back to its plan
# baseline. There is no per-entitlement undo — the previous override sets are
# not recorded anywhere (the audit detail for `clear` is deliberately `{}`,
# because the cleared set is unbounded). Run
# `bin/ots org entitlement show ORG` first if you need to keep a record.
#
# Unlike grant/revoke, clear ALWAYS applies and ALWAYS audits, even when the
# org has no overrides (D15).
require_relative 'entitlement_command'

require_relative '../write_gate'

module Onetime
  module CLI
    class OrgEntitlementClearCommand < Command
      include Org::Shared
      include Org::EntitlementSupport
      include WriteGate

      desc 'Clear ALL entitlement overrides on an organization (destructive)'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid or objid'

      write_gate_options 'Write the override'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, apply: false, dry_run: false, json: false, **)
        boot_application!

        dry_run      = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        organization = resolve_org(org, json: json)

        execute_override(
          organization,
          action: 'clear',
          entitlement: nil,
          dry_run: dry_run,
          json: json,
        )
      end
    end

    register 'organizations entitlement clear', OrgEntitlementClearCommand
  end
end
