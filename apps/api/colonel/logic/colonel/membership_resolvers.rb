# apps/api/colonel/logic/colonel/membership_resolvers.rb
#
# frozen_string_literal: true

module ColonelAPI
  module Logic
    module Colonel
      # Shared org/member resolution for the three membership adapters
      # (AddMembership, RemoveMembership, SetMembershipRole) — #3731.
      #
      # These adapters are thin wrappers over the memberships Operations; the
      # only logic they duplicated was turning a raw identifier into a model.
      # Kept here (not in the global colonel Base) because the extid-or-email
      # lookup order is membership-specific — other colonel logic resolves orgs
      # with a different precedence (see transfer_domain.rb).
      module MembershipResolvers
        private

        # extid first, then objid — user-facing colonel input is an extid.
        def resolve_org(identifier)
          Onetime::Organization.find_by_extid(identifier) ||
            Onetime::Organization.load(identifier)
        end

        # normalize_email is a safe pass-through for an extid (extids are
        # already lowercase ASCII); it only matters when the identifier is an
        # email. load_by_extid_or_email tries extid before email.
        def resolve_customer(identifier)
          Onetime::Customer.load_by_extid_or_email(OT::Utils.normalize_email(identifier))
        end
      end
    end
  end
end
