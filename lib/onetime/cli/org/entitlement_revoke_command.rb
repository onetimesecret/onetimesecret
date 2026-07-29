# lib/onetime/cli/org/entitlement_revoke_command.rb
#
# frozen_string_literal: true

# Add an operator override REVOKE to an organization.
#
# Usage:
#   bin/ots org entitlement revoke ORG ENTITLEMENT --dry-run  # Project, write nothing
#   bin/ots org entitlement revoke ORG ENTITLEMENT            # Confirm, then apply
#   bin/ots org entitlement revoke ORG ENTITLEMENT --yes      # Apply, no prompt
#   bin/ots org entitlement revoke ORG ENTITLEMENT --yes --json
#
# ORG is an org extid or objid (see Onetime::CLI::Org::Shared#resolve_org).
#
# A revoke removes the entitlement from the org's effective set even when the
# plan grants it, and survives every reconcile until cleared. Revoking an
# entitlement the org never had is legal (it pre-empts a later plan change).
require_relative 'entitlement_command'

module Onetime
  module CLI
    class OrgEntitlementRevokeCommand < Command
      include Org::Shared
      include Org::EntitlementSupport

      desc 'Revoke an entitlement from an organization (operator override)'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid or objid'
      argument :entitlement,
        type: :string,
        required: true,
        desc: 'Entitlement name (warns, does not block, when not in the catalog)'

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

      def call(org:, entitlement:, yes: false, dry_run: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)

        execute_override(
          organization,
          action: 'revoke',
          entitlement: entitlement,
          yes: yes,
          dry_run: dry_run,
          json: json,
        )
      end
    end

    register 'org entitlement revoke', OrgEntitlementRevokeCommand
  end
end
