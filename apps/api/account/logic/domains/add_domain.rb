# apps/api/account/logic/domains/add_domain.rb
#
# frozen_string_literal: true

require 'public_suffix'

require 'onetime/cluster'
require_relative '../base'

module AccountAPI::Logic
  module Domains
    class AddDomain < AccountAPI::Logic::Base
      attr_reader :greenlighted, :custom_domain, :domain_input, :display_domain

      def process_params
        # PublicSuffix does its own normalizing so we don't need to do any here
        @domain_input = params['domain'].to_s

        OT.ld "[AddDomain] Parsing #{domain_input}"
      end

      def raise_concerns
        OT.ld "[AddDomain] Raising any concerns about #{@domain_input}"
        # TODO: Consider returning all applicable errors (plural) at once
        raise_form_error 'Please enter a domain' if @domain_input.empty?
        raise_form_error 'Not a valid public domain' unless Onetime::CustomDomain.valid?(@domain_input)

        # Get customer's organization for domain ownership
        org = @cust.organization_instances.first
        raise_form_error 'Customer must belong to an organization' unless org

        # Only store a valid, parsed input value to @domain
        @parsed_domain  = Onetime::CustomDomain.parse(@domain_input, org.orgid)
        @display_domain = @parsed_domain.display_domain

        OT.ld "[AddDomain] Display: #{@display_domain}, Identifier: #{@parsed_domain.identifier}, Exists?: #{@parsed_domain.exists?}"
        raise_form_error 'Duplicate domain' if @parsed_domain.exists?
      end

      def process
        @greenlighted  = true
        OT.ld "[AddDomain] Processing #{@display_domain}"

        # Get customer's organization for domain ownership
        org = @cust.organization_instances.first
        raise_form_error 'Customer must belong to an organization' unless org

        @custom_domain = Onetime::CustomDomain.create!(@display_domain, org.orgid)

        begin
          # Create the approximated vhost for this domain. Approximated provides a
          # custom domain as a service API. If no API key is set, then this will
          # simply log a message and return.
          create_vhost
        rescue HTTParty::ResponseError => ex
          OT.le format('[AddDomain.create_vhost error] %s %s %s', @cust.custid, @display_domain, ex)
          # Continue processing despite vhost error
        end

        success_data
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
          user_id: @cust.objid,
          record: @custom_domain.safe_dump,
          details: {
            cluster: Onetime::Cluster::Features.cluster_safe_dump,
          },
        }
      end
    end
  end
end
