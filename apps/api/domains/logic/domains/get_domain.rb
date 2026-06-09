# apps/api/domains/logic/domains/get_domain.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/features'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    # Get Custom Domain
    #
    # @api Retrieves a custom domain by its external ID. Returns the
    #   domain record and cluster configuration. Verifies ownership
    #   through organization membership.
    class GetDomain < DomainsAPI::Logic::Base
      SCHEMAS = { response: 'customDomain' }.freeze

      attr_reader :greenlighted, :display_domain, :custom_domain

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        raise_form_error 'Please provide a domain ID' if @extid.empty?

        # Get customer's organization for domain ownership
        # Organization available via @organization
        require_organization!

        # Load domain by extid (e.g., dm1234567890)
        # Using extid in the URL path is secure since it's not guessable
        # and we still verify ownership through organization membership
        @custom_domain = Onetime::CustomDomain.find_by_extid(@extid)

        raise_form_error 'Domain not found' unless @custom_domain

        # Verify the customer owns this domain through their organization
        unless @custom_domain.owner?(@cust)
          raise_form_error 'Domain not found'
        end

        # Members can be in the org but cannot view domain details — admin+ required (#3326)
        domain_org = @custom_domain.primary_organization
        raise_form_error 'Domain has no associated organization' unless domain_org
        require_entitlement_in!(domain_org, 'custom_domains')

        # Domain-scope enforcement: deny if member is scoped to a different domain (#3384)
        membership = Onetime::OrganizationMembership.find_by_org_customer(
          domain_org.objid, @cust.objid
        )
        if membership && !membership.can_access_domain?(@custom_domain)
          raise_not_found 'Domain not found'
        end
      end

      def process
        OT.ld "[GetDomain] Processing #{@custom_domain.display_domain}"
        @greenlighted   = true
        @display_domain = @custom_domain.display_domain

        success_data
      end

      def success_data
        {
          user_id: @cust.objid,
          record: custom_domain.safe_dump,
          details: {
            cluster: Onetime::DomainValidation::Features.safe_dump,
          },
        }
      end
    end
  end
end
