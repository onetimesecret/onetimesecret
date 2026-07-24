# apps/api/colonel/logic/colonel/create_custom_domain.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/features'
require 'onetime/operations/domains/create'
require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Create a Custom Domain for a specific organization (Colonel)
      #
      # @api Registers a new custom domain and attaches it to ANY organization,
      #   resolved by public extid (or objid). Validates + normalises the domain
      #   the same way the user-facing DomainsAPI::Logic::Domains::AddDomain does
      #   (PublicSuffix via CustomDomain.valid? / .parse), creates it via the
      #   single audited-elsewhere create path (CustomDomain.create!) and kicks
      #   off SSL certificate provisioning through the configured strategy.
      #   Requires the colonel role.
      #
      # Unlike AddDomain, there is NO org.member? / entitlement gate — the colonel
      # attaches a domain to an org the operator is (by definition) not a member
      # of. That deliberate omission is the whole point of this endpoint.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      #
      # Audit: one AdminAuditEvent per successful create (CONTRACT 4), emitted by
      # {Onetime::Operations::Domains::Create} — this adapter MUST NOT audit.
      # verb is 'domain.create' (the domain.* family: verify/repair/transfer),
      # target is the domain extid, and the org's extid is carried in detail.
      #
      # This class used to own the validate + create + cert + audit sequence
      # inline (create was the last domain verb with no extracted op, so there
      # was no CLI peer). That sequence now lives in the op; the HTTP contract —
      # every error message, field and response key — is unchanged.
      class CreateCustomDomain < ColonelAPI::Logic::Base
        attr_reader :org, :domain_input, :display_domain, :custom_domain, :result

        def process_params
          # Sanitize plain text to strip HTML tags before PublicSuffix normalizes.
          @domain_input = sanitize_plain_text(params['domain'])
          @org_id       = sanitize_identifier(params['org_id'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?

          @org = load_organization
          raise_not_found('Organization not found') unless @org&.exists?

          # Refuse a bad request BEFORE #process. The rules (and their exact
          # operator-facing messages) live in the op so the CLI cannot drift.
          check = operation.validate
          raise_form_error(check.message, field: :domain) unless check.status == :ok

          @display_domain = check.display_domain
          return unless check.claims_orphan

          OT.info "[CreateCustomDomain] Found orphaned domain, will claim: #{@display_domain}"
        end

        def process
          @result = operation.call

          # raise_concerns already validated; a rejection here means the state
          # changed underneath us (a concurrent create claimed the name).
          raise_form_error(result.message, field: :domain) unless result.status == :created

          @custom_domain  = result.domain
          @display_domain = result.display_domain

          success_data
        end

        def success_data
          { record: domain_record, details: domain_details }
        end

        private

        # Memoized so raise_concerns and process share one instance (and one
        # set of resolved inputs).
        def operation
          @operation ||= Onetime::Operations::Domains::Create.new(
            domain: @domain_input,
            org: @org,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
          )
        end

        # Resolve by PUBLIC id (extid) first — every admin surface routes by extid —
        # then fall back to objid. Mirrors GetOrganizationDetail#load_organization.
        def load_organization
          org = Onetime::Organization.find_by_extid(@org_id)
          return org if org

          Onetime::Organization.load(@org_id)
        end

        # safe_dump omits verification_state / resolving / ready (it emits verified
        # but not its siblings), so merge them in — typed to match
        # VerifyCustomDomain's record so the frontend reuses that Zod schema.
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
