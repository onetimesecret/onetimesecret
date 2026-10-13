# apps/web/auth/operations/join_domain_organization.rb
#
# frozen_string_literal: true

module Auth
  module Operations
    # Adds a customer to a custom domain's organization as a member.
    #
    # This operation is called during SSO authentication on custom domains
    # to ensure users who log in via SSO are automatically added to the
    # domain's organization.
    #
    # Flow:
    # 1. SSO login on custom domain (e.g., secrets.company.com)
    # 2. Domain has primary_organization (the company's org)
    # 3. User authenticated → this operation adds them as member
    # 4. OrganizationLoader now returns domain's org (not personal workspace)
    #
    # Login makes two of three separate decisions: it JOINS the customer to
    # the domain org and CHOOSES it as their default (repointing
    # default_org_id away from a personal default workspace they own).
    # RETIRING a workspace is the third decision and belongs to an operator
    # (Onetime::Operations::Org::Delete / Unarchive); the login path never
    # archives an organization (#4717). The personal workspace stays listed
    # and switchable; it does not shadow the domain org because the loader
    # follows the explicit pointer first.
    #
    # Idempotent: If user is already a member, only the default repoint is
    # retried, and it writes nothing when the pointer is already correct.
    #
    # @example
    #   JoinDomainOrganization.new(
    #     customer: customer,
    #     domain_id: 'dom_abc123'
    #   ).call
    #
    class JoinDomainOrganization
      include Onetime::LoggerMethods

      attr_reader :customer, :domain_id

      # @param customer [Onetime::Customer] The authenticated customer
      # @param domain_id [String] The custom domain identifier (domainid)
      def initialize(customer:, domain_id:)
        @customer  = customer
        @domain_id = domain_id
      end

      # Execute the operation
      #
      # @return [Hash] Result with :joined (boolean) and :organization
      def call
        return skip_result('No customer provided') unless customer
        return skip_result('No domain_id provided') if domain_id.to_s.empty?

        # Load the custom domain by objid. domain_id IS the objid here, so use
        # the by-identifier loader (as CustomDomain.from_display_domain does).
        # It returns nil for a missing key and never raises RecordNotFound.
        domain = Onetime::CustomDomain.find_by_identifier(domain_id)
        return skip_result("Domain not found: #{domain_id}") unless domain

        # Get the domain's primary organization
        organization = domain.primary_organization
        return skip_result("Domain has no organization: #{domain_id}") unless organization

        # Check if already a member (includes owner)
        if organization.member?(customer)
          OT.ld "[JoinDomainOrganization] Customer #{customer.custid} already member of #{organization.objid}"

          # Retry the default repoint on subsequent logins: if a previous
          # join succeeded but the repoint failed, the customer is
          # already_member yet still defaulting to a personal workspace.
          adoption = adopt_domain_default_org(organization)

          return {
            joined: false,
            reason: 'already_member',
            organization: organization,
            adoption: adoption,
          }.compact
        end

        # Add as member — activates pending invitation if one exists,
        # otherwise creates membership directly. provisioning_source: 'sso'
        # attributes lifecycle to the JIT path regardless of prior invite state.
        sso_config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(domain.identifier)
        scope_id   = sso_config&.grant_org_scope? ? nil : domain.objid

        membership = Onetime::OrganizationMembership.ensure_membership(
          organization,
          customer,
          role: 'member',
          domain_scope_id: scope_id,
          provisioning_source: 'sso',
        )

        OT.info "[JoinDomainOrganization] Added #{customer.custid} to #{organization.objid} as member (via SSO on #{domain.display_domain})"

        # Self-heal: repoint default_org_id away from a personal workspace
        # to the domain org. Nothing is archived. Also called on the
        # already_member path above (retry for partial failures). Guard
        # conditions in resolve_personal_default_org prevent clobbering
        # intentional multi-org ownership.
        adoption = adopt_domain_default_org(organization)

        {
          joined: true,
          reason: 'added_via_sso',
          organization: organization,
          membership: membership,
          adoption: adoption,
        }.compact
      rescue StandardError => ex
        OT.le "[JoinDomainOrganization] Error: #{ex.message}"
        {
          joined: false,
          reason: 'error',
          error: ex.message,
        }
      end

      private

      def skip_result(reason)
        OT.ld "[JoinDomainOrganization] Skipped: #{reason}"
        { joined: false, reason: reason }
      end

      # After a domain org join, check whether the customer is still
      # defaulting to a personal workspace they own. If so, repoint
      # default_org_id to the domain org so the customer operates in the
      # domain context. The personal workspace is left exactly as it was:
      # live, listed, switchable (#4717 — login never archives).
      #
      # Covers two scenarios:
      #   A. default_org_id explicitly set to the personal workspace
      #   B. default_org_id empty, but a personal workspace with is_default
      #      flag would be selected by OrganizationLoader step 4
      #
      # Conditions are intentionally narrow to avoid clobbering intentional
      # multi-org setups — only fires when the target org has is_default: true,
      # is owned by the customer, and is not archived (legacy state).
      #
      # @param domain_org [Onetime::Organization] The domain org just joined
      # @return [Hash, nil] Adoption result or nil if conditions not met
      def adopt_domain_default_org(domain_org)
        personal_org = resolve_personal_default_org
        return unless personal_org
        # #4717: when the customer owns the domain org and it carries
        # is_default, both resolution paths hand back the destination itself.
        # Compare by objid, not identity: the explicit path loads a separate
        # instance. Repointing an org to itself would be a pointless write
        # reported as an adoption, so return before writing.
        return if personal_org.objid == domain_org.objid

        # One write: the pointer. Individually atomic via Familia's MULTI/EXEC.
        customer.default_org_id = domain_org.objid
        customer.save

        OT.info "[JoinDomainOrganization] Adopted domain org #{domain_org.objid} as default for #{customer.custid}, previous default workspace #{personal_org.objid} left live"

        {
          adopted: true,
          previous_default_org_id: personal_org.objid,
        }
      rescue StandardError => ex
        OT.le "[JoinDomainOrganization] adopt_domain_default_org error (non-fatal): #{ex.message}"
        nil
      end

      # Find the customer's personal default workspace eligible for adoption.
      #
      # First checks default_org_id (explicit pointer): whatever it names is
      # the candidate, and it is adopted only when it is the customer's own
      # live default workspace — a preference for some other organization is
      # left alone, never replaced by a different workspace. If unset, falls
      # back to the default workspace the customer OWNS
      # (OrganizationLoader.owned_default_organization) — the path
      # OrganizationLoader step 4 would take, so repointing the explicit
      # pointer is what stops the loader from returning it. Another member's
      # default workspace carries the is_default flag too; the owned lookup
      # skips it instead of finding it first and giving up.
      #
      # @return [Onetime::Organization, nil]
      def resolve_personal_default_org
        org = resolve_explicit_default_org || resolve_implicit_default_org
        return unless org
        return unless org.is_default
        return if org.archived?
        return unless org.owner?(customer)

        org
      end

      def resolve_explicit_default_org
        default_org_id = customer.default_org_id
        return if default_org_id.to_s.empty?

        Onetime::Organization.load(default_org_id)
      end

      # Owned, non-archived, is_default — selected inside the predicate so a
      # foreign default listed earlier cannot shadow the customer's own.
      def resolve_implicit_default_org
        Onetime::Application::OrganizationLoader.owned_default_organization(customer)
      end
    end
  end
end
