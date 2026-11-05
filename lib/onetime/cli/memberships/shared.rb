# lib/onetime/cli/memberships/shared.rb
#
# frozen_string_literal: true

# Shared resolution + error helpers for the memberships CLI commands
# (add / remove / set-role / entitlement …). Centralizing here mirrors the
# colonel-side MembershipResolvers concern.
#
# ORG resolution is NOT defined here: this module includes Org::Shared, so
# `memberships …` and `organizations …` accept exactly the same ORG grammar
# (extid first, objid fallback, plus the cus_/sub_/hostname forms documented
# on Org::Shared#resolve_org). The CLI has one ORG contract; do not add a
# local resolver here.

# Org::Shared must exist before the `include` below. Required here (not only
# from the lib/onetime/cli.rb manifest) so this file cannot be loaded in a
# broken order.
require_relative '../org/shared'

module Onetime
  module CLI
    module Memberships
      module Shared
        # resolve_org, error_exit, org_label
        include Org::Shared

        # Resolve a CUSTOMER argument to a non-anonymous Onetime::Customer.
        # Accepts everything Customers::Shared#resolve_customer accepts
        # (email, extid, objid, numeric Rodauth account id).
        # @param action [String] verb for the anonymous-rejection message
        #   (e.g. 'add', 'remove', 'set role on').
        def resolve_member(identifier, action:, json:)
          member = resolve_customer(identifier)
          error_exit("Customer not found: #{identifier}", json: json) unless member
          error_exit("Cannot #{action} anonymous customer", json: json) if member.anonymous?
          member
        end
      end
    end
  end
end
