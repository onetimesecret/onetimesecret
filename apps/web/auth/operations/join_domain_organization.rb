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
    # Idempotent: If user is already a member, no-op.
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
        # CustomDomain.load requires (display_domain, org_id) and would raise
        # ArgumentError, logged as an error when not found.
        domain = begin
          Onetime::CustomDomain.find_by_identifier(domain_id)
        rescue Onetime::RecordNotFound
          OT.le "[JoinDomainOrganization] Domain not found (RecordNotFound): #{domain_id}"
          nil
        end
        return skip_result("Domain not found: #{domain_id}") unless domain

        # Get the domain's primary organization
        organization = domain.primary_organization
        return skip_result("Domain has no organization: #{domain_id}") unless organization

        # Check if already a member (includes owner)
        if organization.member?(customer)
          OT.ld "[JoinDomainOrganization] Customer #{customer.custid} already member of #{organization.objid}"

          # Retry adoption on subsequent logins: if a previous join succeeded
          # but adopt_domain_default_org failed partway, the customer is
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
        membership = Onetime::OrganizationMembership.ensure_membership(
          organization,
          customer,
          role: 'member',
          domain_scope_id: domain.objid,
          provisioning_source: 'sso',
        )

        OT.info "[JoinDomainOrganization] Added #{customer.custid} to #{organization.objid} as member (via SSO on #{domain.display_domain})"

        # Self-heal: repoint default_org_id away from personal workspace
        # to the domain org, and soft-archive the personal workspace.
        # Only fires on first join (not already_member) to avoid clobbering
        # intentional multi-org ownership.
        adoption = adopt_domain_default_org(organization)

        {
          joined: true,
          reason: 'added_via_sso',
          organization: organization,
          membership: membership,
          adoption: adoption,
        }
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

      # After a first-time domain org join, check whether the customer is
      # still defaulting to a personal workspace they own. If so, repoint
      # default_org_id to the domain org and soft-archive the personal
      # workspace so the customer operates in the domain context.
      #
      # Covers two scenarios:
      #   A. default_org_id explicitly set to the personal workspace
      #   B. default_org_id empty, but a personal workspace with is_default
      #      flag would be selected by OrganizationLoader step 4
      #
      # Conditions are intentionally narrow to avoid clobbering intentional
      # multi-org setups — only fires when the target org has is_default: true,
      # is owned by the customer, and is not already archived.
      #
      # @param domain_org [Onetime::Organization] The domain org just joined
      # @return [Hash, nil] Adoption result or nil if conditions not met
      def adopt_domain_default_org(domain_org)
        personal_org = resolve_personal_default_org
        return unless personal_org

        # These two writes are intentionally ordered: repointing default_org_id
        # is the higher-priority fix (determines which org the customer sees on
        # next request). If archive! fails after this succeeds, the customer
        # still lands in the domain org — the personal workspace just remains
        # unarchived (benign, and OrganizationLoader's archived? guard prevents
        # it from shadowing the domain org).
        #
        # True cross-model atomicity requires Familia to support multi-instance
        # atomic_write (MULTI/EXEC spanning two Horreum instances). Until then,
        # each save is individually atomic via its own MULTI/EXEC.
        customer.default_org_id = domain_org.objid
        customer.save

        personal_org.archive!("Superseded by domain org #{domain_org.objid} via SSO self-heal")

        OT.info "[JoinDomainOrganization] Adopted domain org #{domain_org.objid} as default for #{customer.custid}, archived personal workspace #{personal_org.objid}"

        {
          adopted: true,
          previous_default_org_id: personal_org.objid,
          archived_org_id: personal_org.objid,
        }
      rescue StandardError => ex
        OT.le "[JoinDomainOrganization] adopt_domain_default_org error (non-fatal): #{ex.message}"
        nil
      end

      # Find the customer's personal default workspace eligible for adoption.
      #
      # First checks default_org_id (explicit pointer). If unset, scans the
      # customer's orgs for one with is_default: true — this is the path
      # OrganizationLoader step 4 would take, so archiving it prevents the
      # loader from returning the stale personal workspace.
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

      def resolve_implicit_default_org
        customer.organization_instances.to_a.find { |o| o.is_default }
      end
    end
  end
end
