# lib/onetime/cli/memberships/shared.rb
#
# frozen_string_literal: true

# Shared resolution + error helpers for the memberships CLI commands
# (add / remove / set-role). These three adapters resolved orgs, members, and
# emitted errors identically; centralizing here mirrors the colonel-side
# MembershipResolvers concern and keeps the "extid-only org lookup" contract
# (documented as `ORG = org extid`) in one place.
module Onetime
  module CLI
    module Memberships
      module Shared
        # Resolve an ORG argument to an Onetime::Organization by extid only.
        # The CLI contract is `ORG = org extid`; unlike the colonel resolver we
        # intentionally do NOT fall back to objid lookup here.
        def resolve_org(identifier, json:)
          organization = Onetime::Organization.find_by_extid(identifier.to_s.strip)
          error_exit("Organization not found: #{identifier}", json: json) unless organization
          organization
        end

        # Resolve a CUSTOMER argument to a non-anonymous Onetime::Customer.
        # @param action [String] verb for the anonymous-rejection message
        #   (e.g. 'add', 'remove', 'set role on').
        def resolve_member(identifier, action:, json:)
          member = resolve_customer(identifier)
          error_exit("Customer not found: #{identifier}", json: json) unless member
          error_exit("Cannot #{action} anonymous customer", json: json) if member.anonymous?
          member
        end

        # Emit an error (JSON or text) and exit non-zero.
        def error_exit(message, json:)
          puts(json ? JSON.generate({ error: message }) : "Error: #{message}")
          exit 1
        end
      end
    end
  end
end
