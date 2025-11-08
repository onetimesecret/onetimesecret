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
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        raise_form_error 'Please enter a domain' if @domain_input.empty?
        raise_form_error 'Not a valid public domain' unless Onetime::CustomDomain.valid?(@domain_input)

        # Getting the domain record based on `req.params[:domain]` (which is
        # the display_domain). That way we need to combine with the custid
        # in order to find it. It's a way of proving ownership. Vs passing the
        # domainid in the URL path which gives up the goods.
        @custom_domain = Onetime::CustomDomain.load(@domain_input, @cust.custid)

        raise_form_error 'Domain not found' unless @custom_domain
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
