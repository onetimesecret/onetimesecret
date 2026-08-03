# lib/onetime/cli/memberships/entitlement_grant_command.rb
#
# frozen_string_literal: true

# Add an operator override GRANT to an organization membership.
#
# Usage:
#   bin/ots memberships entitlement grant ORG CUSTOMER ENTITLEMENT --dry-run  # Project, write nothing
#   bin/ots memberships entitlement grant ORG CUSTOMER ENTITLEMENT            # Confirm, then apply
#   bin/ots memberships entitlement grant ORG CUSTOMER ENTITLEMENT --yes      # Apply, no prompt
#   bin/ots memberships entitlement grant ORG CUSTOMER ENTITLEMENT --yes --json
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

module Onetime
  module CLI
    class MembershipsEntitlementGrantCommand < Command
      include Customers::Shared
      include Memberships::Shared
      include Memberships::EntitlementSupport

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

      # --yes and --dry-run are ORTHOGONAL, matching `org entitlement grant`:
      # --dry-run writes nothing so it needs no confirmation; an applied run
      # always needs --yes (or an interactive 'y').
      def call(org:, customer:, entitlement:, yes: false, dry_run: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'grant entitlement to', json: json)

        execute_override(
          organization,
          member,
          action: 'grant',
          entitlement: entitlement,
          yes: yes,
          dry_run: dry_run,
          json: json,
        )
      end
    end

    register 'memberships entitlement grant', MembershipsEntitlementGrantCommand
  end
end
