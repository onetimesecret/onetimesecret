# lib/onetime/cli/memberships/entitlement_revoke_command.rb
#
# frozen_string_literal: true

# Add an operator override REVOKE to an organization membership.
#
# Usage:
#   bin/ots memberships entitlement revoke ORG CUSTOMER ENTITLEMENT --dry-run  # Project, write nothing
#   bin/ots memberships entitlement revoke ORG CUSTOMER ENTITLEMENT            # Confirm, then apply
#   bin/ots memberships entitlement revoke ORG CUSTOMER ENTITLEMENT --yes      # Apply, no prompt
#   bin/ots memberships entitlement revoke ORG CUSTOMER ENTITLEMENT --yes --json
#
# ORG is an org extid (see Onetime::CLI::Memberships::Shared#resolve_org);
# CUSTOMER is an email, extid, or Rodauth account id.
#
# A revoke is permanent until cleared — there is no TTL. It survives role
# changes and re-materialization, and takes effect even on standalone installs
# (the membership read path has no billing short-circuit).
require_relative 'entitlement_command'

module Onetime
  module CLI
    class MembershipsEntitlementRevokeCommand < Command
      include Customers::Shared
      include Memberships::Shared
      include Memberships::EntitlementSupport

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

      def call(org:, customer:, entitlement:, yes: false, dry_run: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'revoke entitlement from', json: json)

        execute_override(
          organization,
          member,
          action: 'revoke',
          entitlement: entitlement,
          yes: yes,
          dry_run: dry_run,
          json: json,
        )
      end
    end

    register 'memberships entitlement revoke', MembershipsEntitlementRevokeCommand
  end
end
