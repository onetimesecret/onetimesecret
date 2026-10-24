# lib/onetime/cli/memberships/entitlement_grant_command.rb
#
# frozen_string_literal: true

# Add an operator override GRANT to an organization membership.
#
# Usage:
#   bin/ots memberships entitlement grant ORG CUSTOMER ENTITLEMENT            # Dry run (the default): project, write nothing
#   bin/ots memberships entitlement grant ORG CUSTOMER ENTITLEMENT --apply    # Apply
#   bin/ots memberships entitlement grant ORG CUSTOMER ENTITLEMENT --apply --json
#
# ORG is an org extid (see Onetime::CLI::Memberships::Shared#resolve_org);
# CUSTOMER is an email, extid, or Rodauth account id.
#
# A grant is permanent until cleared — there is no TTL. It is NOT bounded by
# the org's plan or the member's role template (the grants set is unioned on
# top of the plan set with no intersection) and survives re-materialization.
# Granting an entitlement that is not in the billing catalog WARNS but is not
# blocked.
require_relative 'entitlement_command'

require_relative '../write_gate'

module Onetime
  module CLI
    class MembershipsEntitlementGrantCommand < Command
      include Customers::Shared
      include Memberships::Shared
      include Memberships::EntitlementSupport
      include WriteGate

      desc 'Grant an entitlement to an org member (operator override)'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid'
      argument :customer,
        type: :string,
        required: true,
        desc: 'Member email, extid, or Rodauth account ID'
      argument :entitlement,
        type: :string,
        required: true,
        desc: 'Entitlement name (warns, does not block, when not in the catalog)'

      write_gate_options 'Write the override'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, customer:, entitlement:, apply: false, dry_run: false, json: false, **)
        boot_application!

        dry_run      = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'grant entitlement to', json: json)

        execute_override(
          organization,
          member,
          action: 'grant',
          entitlement: entitlement,
          dry_run: dry_run,
          json: json,
        )
      end
    end

    register 'memberships entitlement grant', MembershipsEntitlementGrantCommand
  end
end
