# apps/api/account/logic/domains/get_domain.rb
#
# frozen_string_literal: true

require 'onetime/cluster'
require_relative '../base'

module AccountAPI::Logic
  module Domains
    class GetDomain < AccountAPI::Logic::Base
      attr_reader :greenlighted, :display_domain, :custom_domain

      def process_params
        @extid = params['extid'].to_s.strip
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
            cluster: Onetime::Cluster::Features.cluster_safe_dump,
          },
        }
      end
    end
  end
end
