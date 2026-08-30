# apps/api/colonel/logic/colonel/domain_resolver.rb
#
# frozen_string_literal: true

module ColonelAPI
  module Logic
    module Colonel
      # Shared custom-domain resolution for the colonel domain endpoints.
      #
      # Resolve by PUBLIC id (extid, `cd…`) first — every admin surface routes
      # by extid — then fall back to the internal objid (domain_id), which the
      # list endpoint also exposes and operators paste from logs and support
      # tickets. Mirrors the organization endpoints' extid-then-objid order
      # (GetOrganizationDetail#load_organization, MembershipResolvers).
      #
      # Both arms are O(1) index/key gets, never scans. The objid arm is
      # rescued: `CustomDomain.load` can raise on input the identifier codec
      # rejects, and a garbage identifier must read as "not found", not a 500.
      module DomainResolver
        # @param identifier [String] a custom domain extid or objid (domain_id)
        # @return [Onetime::CustomDomain, nil]
        def resolve_custom_domain(identifier)
          domain = Onetime::CustomDomain.find_by_extid(identifier)
          return domain if domain

          domain = begin
            Onetime::CustomDomain.load(identifier)
          rescue StandardError
            nil
          end
          domain&.exists? ? domain : nil
        end
      end
    end
  end
end
