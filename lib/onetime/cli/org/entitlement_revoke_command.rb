# lib/onetime/cli/org/entitlement_revoke_command.rb
#
# frozen_string_literal: true

# Add an operator override REVOKE to an organization.
#
# Usage:
#   bin/ots org entitlement revoke ORG ENTITLEMENT            # Dry run (the default): project, write nothing
#   bin/ots org entitlement revoke ORG ENTITLEMENT --apply    # Apply
#   bin/ots org entitlement revoke ORG ENTITLEMENT --apply --json
#
# ORG is an org extid or objid (see Onetime::CLI::Org::Shared#resolve_org).
#
# A revoke removes the entitlement from the org's effective set even when the
# plan grants it, and survives every reconcile until cleared. Revoking an
# entitlement the org never had is legal (it pre-empts a later plan change).
require_relative 'entitlement_command'

require_relative '../write_gate'

module Onetime
  module CLI
    class OrgEntitlementRevokeCommand < Command
      include Org::Shared
      include Org::EntitlementSupport
      include WriteGate

      desc 'Revoke an entitlement from an organization (operator override)'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid or objid'
      argument :entitlement,
        type: :string,
        required: true,
        desc: 'Entitlement name (warns, does not block, when not in the catalog)'

      write_gate_options 'Write the override'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, entitlement:, apply: false, dry_run: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)

        execute_override(
          organization,
          action: 'revoke',
          entitlement: entitlement,
          apply: apply,
          dry_run: dry_run,
          json: json,
        )
      end
    end

    register 'organizations entitlement revoke', OrgEntitlementRevokeCommand
  end
end
