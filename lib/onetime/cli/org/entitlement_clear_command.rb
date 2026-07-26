# lib/onetime/cli/org/entitlement_clear_command.rb
#
# frozen_string_literal: true

# Wipe ALL operator entitlement overrides on an organization.
#
# Usage:
#   bin/ots org entitlement clear ORG --dry-run   # Project the result, write nothing
#   bin/ots org entitlement clear ORG             # Confirm, then apply
#   bin/ots org entitlement clear ORG --yes       # Apply, no prompt
#   bin/ots org entitlement clear ORG --yes --json
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

module Onetime
  module CLI
    class OrgEntitlementClearCommand < Command
      include Org::Shared
      include Org::EntitlementSupport

      desc 'Clear ALL entitlement overrides on an organization (destructive)'

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
        desc: 'Project the resulting override sets; write nothing'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, yes: false, dry_run: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)

        execute_override(
          organization,
          action: 'clear',
          entitlement: nil,
          yes: yes,
          dry_run: dry_run,
          json: json,
        )
      end
    end

    register 'org entitlement clear', OrgEntitlementClearCommand
  end
end
