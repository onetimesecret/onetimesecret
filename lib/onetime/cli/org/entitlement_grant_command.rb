# lib/onetime/cli/org/entitlement_grant_command.rb
#
# frozen_string_literal: true

# Add an operator override GRANT to an organization.
#
# Usage:
#   bin/ots org entitlement grant ORG ENTITLEMENT             # Dry run (the default): project, write nothing
#   bin/ots org entitlement grant ORG ENTITLEMENT --apply     # Apply
#   bin/ots org entitlement grant ORG ENTITLEMENT --apply --json
#
# ORG is an org extid or objid (see Onetime::CLI::Org::Shared#resolve_org).
#
# A grant is permanent until cleared — there is no TTL (D18). Granting an
# entitlement that is not in the billing catalog WARNS but is not blocked.
require_relative 'entitlement_command'

require_relative '../write_gate'

module Onetime
  module CLI
    class OrgEntitlementGrantCommand < Command
      include Org::Shared
      include Org::EntitlementSupport
      include WriteGate

      desc 'Grant an entitlement to an organization (operator override)'

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
          action: 'grant',
          entitlement: entitlement,
          apply: apply,
          dry_run: dry_run,
          json: json,
        )
      end
    end

    register 'organizations entitlement grant', OrgEntitlementGrantCommand
  end
end
