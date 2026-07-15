# lib/onetime/operations/memberships/support.rb
#
# frozen_string_literal: true

module Onetime
  module Operations
    module Memberships
      # Shared safety guardrail for the membership mutation ops (set-role /
      # remove). The "sole remaining owner" invariant is a correctness rule, not
      # a UX nicety: removing or demoting the last owner would orphan the org
      # (nobody could manage billing, members, or SSO — every `manage_org` path
      # would deny). Living here keeps the check IDENTICAL across both the
      # SetRole and Remove ops, so the colonel endpoint and the CLI can never
      # drift into different definitions of "last owner".
      module Support
        # @param org [Onetime::Organization]
        # @param membership [Onetime::OrganizationMembership] the target membership
        # @return [Boolean] true when +membership+ is an owner AND the org has no
        #   other active owner (removing/demoting it would leave zero owners).
        def sole_owner?(org, membership)
          return false unless membership.owner?

          Onetime::OrganizationMembership.active_for_org(org).count(&:owner?) <= 1
        end
      end
    end
  end
end
