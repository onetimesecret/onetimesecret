# lib/onetime/cli/memberships/entitlement_revoke_command.rb
#
# frozen_string_literal: true

# Add an operator override REVOKE to an organization membership.
#
# Usage:
#   bin/ots memberships entitlement revoke ORG CUSTOMER ENTITLEMENT            # Dry run (the default): project, write nothing
#   bin/ots memberships entitlement revoke ORG CUSTOMER ENTITLEMENT --apply    # Apply
#   bin/ots memberships entitlement revoke ORG CUSTOMER ENTITLEMENT --apply --json
#
# ORG is an org extid (see Onetime::CLI::Memberships::Shared#resolve_org);
# CUSTOMER is an email, extid, or Rodauth account id.
#
# A revoke is permanent until cleared — there is no TTL. It survives role
# changes and re-materialization, and takes effect even on standalone installs
# (the membership read path has no billing short-circuit).
require_relative 'entitlement_command'

require_relative '../write_gate'

module Onetime
  module CLI
    class MembershipsEntitlementRevokeCommand < Command
      include Customers::Shared
      include Memberships::Shared
      include Memberships::EntitlementSupport
      include WriteGate

      desc 'Revoke an entitlement from an org member (operator override)'

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
        desc: 'Entitlement name'

      write_gate_options 'Write the override'
      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(org:, customer:, entitlement:, apply: false, dry_run: false, json: false, **)
        boot_application!

        dry_run      = dry_run_unless_applied(apply: apply, dry_run: dry_run, json: json)
        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'revoke entitlement from', json: json)

        execute_override(
          organization,
          member,
          action: 'revoke',
          entitlement: entitlement,
          dry_run: dry_run,
          json: json,
        )
      end
    end

    register 'memberships entitlement revoke', MembershipsEntitlementRevokeCommand
  end
end
