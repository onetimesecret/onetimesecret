require 'onetime/cluster'
require_relative '../base'

module V2::Logic
  module Domains
    class RemoveDomain < V2::Logic::Base
      attr_reader :greenlighted, :domain_input, :display_domain
      def process_params
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        raise_form_error 'Please enter a domain' if @domain_input.empty?
        raise_form_error 'Not a valid public domain' unless V2::CustomDomain.valid?(@domain_input)

        limit_action :remove_domain

        @custom_domain = V2::CustomDomain.load(@domain_input, @cust.custid)
        raise_form_error 'Domain not found' unless @custom_domain
      end

      def process
        OT.ld "[RemoveDomain] Processing #{domain_input} for #{@custom_domain.identifier}"
        @greenlighted = true
        @display_domain = @custom_domain.display_domain

        # Destroy method operates inside a multi block that deletes the domain
        # record, removes it from customer's domain list, and global list so
        # it's all or nothing. It does not delete the external approximated
        # vhost record.
        @custom_domain.destroy!(@cust)
      end

      def delete_vhost
        api_key = Onetime::Cluster::Features.api_key
        if api_key.to_s.empty?
          return OT.info '[RemoveDomain.delete_vhost] Approximated API key not set'
        end
        res = Onetime::Cluster::Approximated.delete_vhost(api_key, @display_domain)
        payload = res.parsed_response
        OT.info '[RemoveDomain.delete_vhost] %s' % payload
      rescue HTTParty::ResponseError => e
        OT.le '[RemoveDomain.delete_vhost error] %s %s %s'  % [@cust.custid, @display_domain, e]
      end

      def success_data
        {
          custid: @cust.custid,
          record: {},
          message: "Removed #{display_domain}",
        }
      end
    end
  end
end
