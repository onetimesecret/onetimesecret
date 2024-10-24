require 'public_suffix'

require_relative '../base'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    class AddDomain < OT::Logic::Base
      attr_reader :greenlighted, :custom_domain

      def process_params
        OT.ld "[AddDomain] Parsing #{params[:domain]}"
         # PublicSuffix does its own normalizing so we don't need to do any here
         @domain_input = params[:domain].to_s
      end

      def raise_concerns
        OT.ld "[AddDomain] Raising any concerns about #{@domain_input}"
        # TODO: Consider returning all applicable errors (plural) at once
        raise_form_error "Please enter a domain" if @domain_input.empty?
        raise_form_error "Not a valid public domain" unless OT::CustomDomain.valid?(@domain_input)

        limit_action :add_domain

        # Only store a valid, parsed input value to @domain
        @parsed_domain = OT::CustomDomain.parse(@domain_input, @cust) # raises OT::Problem
        @display_domain = @parsed_domain.display_domain

        # Don't need to do a bunch of validation checks here. If the input value
        # passes as valid, it's valid. If another account has verified the same
        # domain, that's fine. Both accounts can generate secret links for that
        # domain, and the links will be valid for both accounts.
        #
        #   e.g. `OT::CustomDomain.exists?(@domain)`
      end

      def process
        @greenlighted = true
        OT.ld "[AddDomain] Processing #{@display_domain}"
        @custom_domain = OT::CustomDomain.create(@display_domain, @cust.custid)

        # Create the approximated vhost for this domain. Approximated provides a
        # custom domain as a service API. If no API key is set, then this will
        # simply log a message and return.
        create_vhost
      end

      def create_vhost
        api_key = OT::Cluster::Features.api_key
        vhost_target = OT::Cluster::Features.vhost_target

        if api_key.to_s.empty?
          return OT.info "[AddDomain.create_vhost] Approximated API key not set"
        end

        res = OT::Cluster::Approximated.create_vhost(api_key, @display_domain, vhost_target, '443')
        payload = res.parsed_response

        OT.info "[AddDomain.create_vhost] %s" % payload
        custom_domain.vhost = payload['data'].to_json
        custom_domain.updated = OT.now.to_i
        custom_domain.save

      rescue HTTParty::ResponseError => e
        OT.le "[AddDomain.create_vhost error] %s %s %s"  % [@cust.custid, @display_domain, e]
      end

      def success_data
        {
          custid: @cust.custid,
          record: @custom_domain.safe_dump,
          details: {
            cluster: OT::Cluster::Features.cluster_safe_dump
          }
        }
      end
    end
  end
end