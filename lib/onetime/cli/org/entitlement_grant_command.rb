# lib/onetime/cli/org/entitlement_grant_command.rb
#
# frozen_string_literal: true

# Add an operator override GRANT to an organization.
#
# Usage:
#   bin/ots org entitlement grant ORG ENTITLEMENT --dry-run   # Project, write nothing
#   bin/ots org entitlement grant ORG ENTITLEMENT             # Confirm, then apply
#   bin/ots org entitlement grant ORG ENTITLEMENT --yes       # Apply, no prompt
#   bin/ots org entitlement grant ORG ENTITLEMENT --yes --json
#
# ORG is an org extid or objid (see Onetime::CLI::Org::Shared#resolve_org).
#
# A grant is permanent until cleared — there is no TTL (D18). Granting an
# entitlement that is not in the billing catalog WARNS but is not blocked.
require_relative 'entitlement_command'

module Onetime
  module CLI
    class OrgEntitlementGrantCommand < Command
      include Org::Shared
      include Org::EntitlementSupport

      desc 'Grant an entitlement to an organization (operator override)'

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

      # --yes and --dry-run are ORTHOGONAL, matching `org reconcile`: --dry-run
      # writes nothing so it needs no confirmation; an applied run always needs
      # --yes (or an interactive 'y').
      def call(org:, entitlement:, yes: false, dry_run: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)

        execute_override(
          organization,
          action: 'grant',
          entitlement: entitlement,
          yes: yes,
          dry_run: dry_run,
          json: json,
        )
      end
    end

    register 'org entitlement grant', OrgEntitlementGrantCommand
  end
end
