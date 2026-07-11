# apps/api/colonel/logic/colonel/get_custom_domain.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/features'
require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Get Custom Domain detail (Colonel)
      #
      # @api Full read-out for a single custom domain, resolved globally by its
      #   PUBLIC id (extid). Backs the admin DNS-details panel and the refresh
      #   after a colonel re-verify. Same response shape as CreateCustomDomain:
      #   { record: safe_dump (+ DNS fields), details: { cluster } }.
      #   Requires the colonel role.
      #
      # Colonel access is cross-organization: like VerifyCustomDomain / ProbeDomain,
      # any domain resolves by extid with NO ownership/membership gate.
      #
      # READ-ONLY: emits NO AdminAuditEvent (CONTRACT 4 — audit is for mutations),
      # matching ProbeDomain / GetSessionDetail.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class GetCustomDomain < ColonelAPI::Logic::Base
        attr_reader :extid, :custom_domain

        def process_params
          @extid = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Domain ID is required', field: :extid) if extid.to_s.empty?

          @custom_domain = Onetime::CustomDomain.find_by_extid(extid)
          raise_not_found('Domain not found') unless custom_domain
        end

        def process
          success_data
        end

        def success_data
          { record: domain_record, details: domain_details }
        end

        private

        # safe_dump omits verification_state / resolving / ready — merge them in,
        # typed to match VerifyCustomDomain / CreateCustomDomain so the frontend
        # shares one Zod schema across all three colonel domain responses.
        #
        # domain_id overrides safe_dump's own `domainid` (no underscore) key —
        # every other colonel domain response (VerifyCustomDomain, ListCustomDomains,
        # RepairDomain, TransferDomain) uses `domain_id`, and the frontend Zod
        # schema (colonelDomainDetailRecordSchema) requires it.
        def domain_record
          custom_domain.safe_dump.merge(
            domain_id: custom_domain.domainid,
            verification_state: custom_domain.verification_state.to_s,
            resolving: custom_domain.resolving.to_s == 'true',
            ready: custom_domain.ready?,
          )
        end

        def domain_details
          { cluster: Onetime::DomainValidation::Features.safe_dump }
        end
      end
    end
  end
end
