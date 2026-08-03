# lib/onetime/cli/memberships/entitlement_clear_command.rb
#
# frozen_string_literal: true

# Wipe ALL operator entitlement overrides on an organization membership.
#
# Usage:
#   bin/ots memberships entitlement clear ORG CUSTOMER --dry-run  # Project the result, write nothing
#   bin/ots memberships entitlement clear ORG CUSTOMER            # Confirm, then apply
#   bin/ots memberships entitlement clear ORG CUSTOMER --yes      # Apply, no prompt
#   bin/ots memberships entitlement clear ORG CUSTOMER --yes --json
#
# ORG is an org extid (see Onetime::CLI::Memberships::Shared#resolve_org);
# CUSTOMER is an email, extid, or Rodauth account id.
#
# This is THE destructive verb of the group: it empties `entitlements_grants`
# AND `entitlements_revokes`, then re-reconciles the membership back to its
# role baseline (org ∩ role template). There is no per-entitlement undo — the
# previous override sets are not recorded anywhere (the audit detail records
# only org_id, because the cleared set is unbounded). Run
# `bin/ots memberships entitlement show ORG CUSTOMER` first if you need to
# keep a record.
#
# Unlike grant/revoke, clear ALWAYS applies and ALWAYS audits, even when the
# membership has no overrides (D15).
require_relative 'entitlement_command'

module Onetime
  module CLI
    class MembershipsEntitlementClearCommand < Command
      include Customers::Shared
      include Memberships::Shared
      include Memberships::EntitlementSupport

      desc 'Clear ALL entitlement overrides on an org member (destructive)'

      argument :org,
        type: :string,
        required: true,
        desc: 'Organization extid'
      argument :customer,
        type: :string,
        required: true,
        desc: 'Member email, extid, or Rodauth account ID'

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

      def call(org:, customer:, yes: false, dry_run: false, json: false, **)
        boot_application!

        organization = resolve_org(org, json: json)
        member       = resolve_member(customer, action: 'clear entitlement overrides on', json: json)

        execute_override(
          organization,
          member,
          action: 'clear',
          entitlement: nil,
          yes: yes,
          dry_run: dry_run,
          json: json,
        )
      end
    end

    register 'memberships entitlement clear', MembershipsEntitlementClearCommand
  end
end
