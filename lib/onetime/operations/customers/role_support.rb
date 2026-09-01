# lib/onetime/operations/customers/role_support.rb
#
# frozen_string_literal: true

module Onetime
  module Operations
    module Customers
      # Shared predicates for system-role and verification changes (#4328).
      #
      # Lives here — not in the colonel adapter — so the definition of "the last
      # colonel" is IDENTICAL for the HTTP endpoints and for
      # `bin/ots customers role demote`. Same reasoning as
      # {Onetime::Operations::Memberships::Support#sole_owner?}, which the
      # membership ops share with their CLI for exactly this reason.
      #
      # `extend self` (not module_function) is the in-repo idiom and what
      # Style/ModuleFunction enforces: callers may either `include` the module
      # (the ops do, so the predicates read as plain calls) or address it
      # directly as `RoleSupport.last_colonel?(...)` (the adapters do).
      module RoleSupport
        extend self

        # Every account that is authoritatively a colonel RIGHT NOW.
        #
        # Customer.colonel_count / role_index_for read a DERIVED index that is
        # known to drift UPWARD (reconcile_role_index.rb documents both
        # mechanisms: familia 2.12 partial writes are add-only and retain the
        # previous role's bucket member, and a TTL-expired customer hash leaves
        # its index member behind forever). Counting the index would make a
        # last-colonel guard FAIL OPEN — the exact failure mode #4328 exists to
        # prevent — so every member is re-checked against the authoritative
        # `role` field. `verified?` matches has_system_role?, which refuses the
        # colonel role to an unverified account; that is also why unverifying
        # the last colonel is itself an interlocked action.
        #
        # Bounded cost: the colonel bucket holds a handful of accounts in every
        # real install, and this is only reached on a role or verification
        # CHANGE — never on the read path.
        #
        # @return [Array<Onetime::Customer>]
        def active_colonels
          Onetime::Customer.find_all_by_role('colonel').select do |candidate|
            candidate && candidate.exists? && candidate.role.to_s == 'colonel' && candidate.verified?
          end
        end

        # Would demoting this customer leave the install with no colonel?
        #
        # @param customer [Onetime::Customer] the demotion target
        # @param to_role [String, Symbol] the role being assigned
        # @return [Boolean]
        def last_colonel?(customer, to_role)
          return false if to_role.to_s == 'colonel'
          return false unless customer.role.to_s == 'colonel'

          sole_active_colonel?(customer)
        end

        # Would UNVERIFYING this customer leave the install with no colonel?
        #
        # Unverification strips colonel eligibility through has_system_role?'s
        # verified? check, so it is a demotion by another name — and it was
        # reachable straight past any last-colonel check on the role endpoint.
        #
        # @param customer [Onetime::Customer] the unverify target
        # @return [Boolean]
        def last_colonel_by_verification?(customer)
          return false unless customer.role.to_s == 'colonel'
          return false unless customer.verified?

          sole_active_colonel?(customer)
        end

        # True when no OTHER account is an active colonel. Identity is compared
        # on objid (the internal id), matching purge_user.rb's self-target
        # comparison; extid would work too but objid is what every other
        # same-account check in this codebase uses.
        #
        # @param customer [Onetime::Customer]
        # @return [Boolean]
        def sole_active_colonel?(customer)
          active_colonels.none? { |candidate| candidate.objid != customer.objid }
        end
      end
    end
  end
end
