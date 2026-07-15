# apps/api/colonel/logic/colonel/create_custom_domain.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/features'
require 'onetime/domain_validation/strategy'
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
      # Audit: one AdminAuditEvent per successful create (CONTRACT 4). No Operation
      # has been extracted for the create verb yet, so the audit backstop lives in
      # this logic layer — matching ReconcileOrganization / ManageEntitlementOverride.
      # verb is 'domain.create' (the domain.* family: verify/repair/transfer),
      # target is the domain extid, and the org's extid is carried in detail.
      class CreateCustomDomain < ColonelAPI::Logic::Base
        AUDIT_VERB = 'domain.create'

        attr_reader :org, :domain_input, :display_domain, :custom_domain

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

          # Domain validation — identical to AddDomain#raise_concerns, minus the
          # membership/entitlement gate. Reuse the model regex; don't reinvent it.
          raise_form_error('Please enter a domain', field: :domain) if @domain_input.to_s.empty?
          raise_form_error('Not a valid public domain', field: :domain) unless Onetime::CustomDomain.valid?(@domain_input)
          raise_form_error('This domain overlaps with the default site domain', field: :domain) if Onetime::CustomDomain.overlaps_canonical_domain?(@domain_input)

          # Normalise to the parsed display_domain (mirrors AddDomain).
          parsed          = Onetime::CustomDomain.parse(@domain_input, @org.objid)
          @display_domain = parsed.display_domain

          # Pre-check duplicates for precise errors (create! re-checks atomically).
          existing = Onetime::CustomDomain.load_by_display_domain(@display_domain)
          return unless existing

          if existing.org_id.to_s == @org.objid.to_s
            raise_form_error('Domain already registered in this organization', field: :domain)
          end

          unless existing.org_id.to_s.empty?
            raise_form_error('Domain is registered to another organization', field: :domain)
          end

          # Orphaned domain (no org_id): create! claims it in #process.
          OT.info "[CreateCustomDomain] Found orphaned domain, will claim: #{@display_domain}"
        end

        def process
          # Atomicity: the #raise_concerns duplicate/orphan pre-checks run in a
          # separate step and can race a concurrent colonel request — they are
          # advisory (for precise field errors), NOT for correctness. create! is
          # the sole atomic gate: HSETNX on display_domain_index claims a new
          # domain, and claim_orphaned_domain uses a pinned-connection WATCH/MULTI
          # to claim an orphan. The concurrent request that loses the gate gets an
          # Onetime::Problem re-raised here, so no double-registration occurs.
          @custom_domain = Onetime::CustomDomain.create!(@display_domain, @org.objid)

          begin
            request_certificate
          rescue HTTParty::ResponseError => ex
            OT.le "[CreateCustomDomain.request_certificate error] org=#{org.extid} display_domain=#{@display_domain} exception=#{ex}"
            # Continue: the domain exists; cert provisioning can be retried.
          rescue StandardError => ex
            OT.le "[CreateCustomDomain] Unexpected error during certificate request: #{ex}"
            # Continue: the domain exists; cert provisioning can be retried.
          end

          record_audit_event

          OT.info "[CreateCustomDomain] #{@display_domain} -> org=#{org.extid} extid=#{custom_domain.extid}"

          success_data
        end

        def request_certificate
          strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)
          result   = strategy.request_certificate(@custom_domain)

          OT.info "[CreateCustomDomain.request_certificate] #{@display_domain} -> #{result[:status]}"

          if result[:data]
            @custom_domain.vhost   = result[:data].to_json
            @custom_domain.updated = OT.now.to_i
            @custom_domain.save
          end

          result
        end

        def success_data
          { record: domain_record, details: domain_details }
        end

        private

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

        def record_audit_event
          Onetime::AdminAuditEvent.record(
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
            verb: AUDIT_VERB,
            target: custom_domain.extid,
            result: :success,
            detail: {
              org_id: org.extid,
              display_domain: custom_domain.display_domain,
            },
          )
        end
      end
    end
  end
end
