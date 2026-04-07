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

        # Load the custom domain
        domain = Onetime::CustomDomain.load(domain_id)
        return skip_result("Domain not found: #{domain_id}") unless domain

        # Get the domain's primary organization
        organization = domain.primary_organization
        return skip_result("Domain has no organization: #{domain_id}") unless organization

        # Check if already a member (includes owner)
        if organization.member?(customer)
          OT.ld "[JoinDomainOrganization] Customer #{customer.custid} already member of #{organization.objid}"
          return {
            joined: false,
            reason: 'already_member',
            organization: organization,
          }
        end

        # Add as member — activates pending invitation if one exists,
        # otherwise creates membership directly
        membership = Onetime::OrganizationMembership.ensure_membership(
          organization, customer, role: 'member'
        )

        OT.info "[JoinDomainOrganization] Added #{customer.custid} to #{organization.objid} as member (via SSO on #{domain.display_domain})"

        {
          joined: true,
          reason: 'added_via_sso',
          organization: organization,
          membership: membership,
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
    end
  end
end
