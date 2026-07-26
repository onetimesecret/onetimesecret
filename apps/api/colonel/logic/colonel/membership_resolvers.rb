# apps/api/colonel/logic/colonel/membership_resolvers.rb
#
# frozen_string_literal: true

require_relative 'account_identifier'

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
        include AccountIdentifier

        private

        # extid first, then objid — user-facing colonel input is an extid.
        def resolve_org(identifier)
          Onetime::Organization.find_by_extid(identifier) ||
            Onetime::Organization.load(identifier)
        end

        # normalize_email is a safe pass-through for an extid (extids are
        # already lowercase ASCII); it only matters when the identifier is an
        # email. load_by_extid_or_email tries extid before email.
        #
        # NOTE: the caller MUST sanitize the raw param with
        # {AccountIdentifier#sanitize_account_identifier}, not
        # `sanitize_identifier` — the latter strips '@' and '.', turning
        # `user@example.com` into `userexamplecom` and making this email arm
        # permanently unreachable.
        def resolve_customer(identifier)
          resolve_account(identifier)
        end
      end
    end
  end
end
