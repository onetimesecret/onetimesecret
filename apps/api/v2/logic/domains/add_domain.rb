require 'public_suffix'

# Tryouts: tests/unit/ruby/try/60_logic/41_logic_domains_add_try.rb

require 'onetime/cluster'
require_relative '../base'

module V2::Logic
  module Domains
    class AddDomain < V2::Logic::Base
      attr_reader :greenlighted, :custom_domain, :domain_input, :display_domain

      def process_params
        OT.ld "[AddDomain] Parsing #{params[:domain]}"
        # PublicSuffix does its own normalizing so we don't need to do any here
        @domain_input = params[:domain].to_s
      end

      def raise_concerns
        OT.ld "[AddDomain] Raising any concerns about #{@domain_input}"
        # TODO: Consider returning all applicable errors (plural) at once
        raise_form_error 'Please enter a domain' if @domain_input.empty?
        raise_form_error 'Not a valid public domain' unless V2::CustomDomain.valid?(@domain_input)

        # Only store a valid, parsed input value to @domain
        @parsed_domain  = V2::CustomDomain.parse(@domain_input, @cust.custid)
        @display_domain = @parsed_domain.display_domain

        OT.ld "[AddDomain] Display: #{@display_domain}, Identifier: #{@parsed_domain.identifier}, Exists?: #{@parsed_domain.exists?}"
        raise_form_error 'Duplicate domain' if @parsed_domain.exists?
      end

      def process
        @greenlighted  = true
        OT.ld "[AddDomain] Processing #{@display_domain}"
        @custom_domain = V2::CustomDomain.create(@display_domain, @cust.custid)

        begin
          # Create the approximated vhost for this domain. Approximated provides a
          # custom domain as a service API. If no API key is set, then this will
          # simply log a message and return.
          create_vhost
        rescue HTTParty::ResponseError => ex
          OT.le format('[AddDomain.create_vhost error] %s %s %s', @cust.custid, @display_domain, ex)
          # Continue processing despite vhost error
        end
      end

      def create_vhost
        api_key      = Onetime::Cluster::Features.api_key
        vhost_target = Onetime::Cluster::Features.vhost_target

        return OT.info '[AddDomain.create_vhost] Approximated API key not set' if api_key.to_s.empty?

        res     = Onetime::Cluster::Approximated.create_vhost(api_key, @display_domain, vhost_target, '443')
        payload = res.parsed_response

        OT.info '[AddDomain.create_vhost] %s' % payload
        custom_domain.vhost   = payload['data'].to_json
        custom_domain.updated = OT.now.to_i
        custom_domain.save
      end

      def success_data
        {
          custid: @cust.custid,
          record: @custom_domain.safe_dump,
          details: {
            cluster: Onetime::Cluster::Features.cluster_safe_dump,
          },
        }
      end
    end
  end
end
