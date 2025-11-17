# apps/api/domains/logic/domains/remove_domain.rb
#
# frozen_string_literal: true

require 'onetime/cluster'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    class RemoveDomain < DomainsAPI::Logic::Base
      attr_reader :greenlighted, :extid, :display_domain

      def process_params
        @extid = params['extid'].to_s.strip
      end

      def raise_concerns
        raise_form_error 'Please provide a domain ID' if @extid.empty?

        # Get customer's organization for domain ownership
        # Organization available via @organization
        require_organization!

        @custom_domain = Onetime::CustomDomain.find_by_extid(@extid)
        raise_form_error 'Domain not found' unless @custom_domain

        # Verify the customer owns this domain through their organization
        unless @custom_domain.owner?(@cust)
          raise_form_error 'Domain not found'
        end
      end

      def process
        OT.ld "[RemoveDomain] Processing #{@extid} (#{@custom_domain.display_domain})"
        @greenlighted   = true
        @display_domain = @custom_domain.display_domain

        # Destroy method operates inside a multi block that deletes the domain
        # record, removes it from customer's domain list, and global list so
        # it's all or nothing. It does not delete the external approximated
        # vhost record.
        @custom_domain.destroy!(@cust)

        success_data
      end

      def delete_vhost
        api_key = Onetime::Cluster::Features.api_key
        return OT.info '[RemoveDomain.delete_vhost] Approximated API key not set' if api_key.to_s.empty?

        res     = Onetime::Cluster::Approximated.delete_vhost(api_key, @display_domain)
        payload = res.parsed_response
        OT.info '[RemoveDomain.delete_vhost] %s' % payload
      rescue HTTParty::ResponseError => ex
        OT.le format('[RemoveDomain.delete_vhost error] %s %s %s', @cust.custid, @display_domain, ex)
      end

      def success_data
        {
          user_id: @cust.objid,
          record: {},
          message: "Removed #{display_domain}",
        }
      end
    end
  end
end
