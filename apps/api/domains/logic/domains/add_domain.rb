# apps/api/domains/logic/domains/add_domain.rb
#
# frozen_string_literal: true

require 'public_suffix'

require 'onetime/cluster'
require 'onetime/domain_validation/strategy'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    class AddDomain < DomainsAPI::Logic::Base
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

        # Require organization for domain ownership
        require_organization!

        # Check custom domains entitlement
        unless organization.can?('custom_domains')
          raise_form_error 'Upgrade required for custom domains', field: :domain, error_type: :upgrade_required
        end

        # Only store a valid, parsed input value to @domain
        @parsed_domain  = Onetime::CustomDomain.parse(@domain_input, organization.objid)
        @display_domain = @parsed_domain.display_domain

        OT.ld "[AddDomain] Display: #{@display_domain}, Identifier: #{@parsed_domain.identifier}"

        # Check for existing domain to provide specific error messages
        existing = Onetime::CustomDomain.load_by_display_domain(@display_domain)

        return unless existing

        # Scenario 1: Domain already in customer's organization (same org_id)
        if existing.org_id.to_s == organization.objid.to_s
          OT.ld "[AddDomain] Domain already in organization: #{@display_domain}"
          raise_form_error 'Domain already registered in your organization'
        end

        # Scenario 2: Domain in another organization (different org_id)
        unless existing.org_id.to_s.empty?
          OT.le "[AddDomain] Domain belongs to another organization: #{@display_domain}"
          raise_form_error 'Domain is registered to another organization'
        end

        # Scenario 3: Orphaned domain (no org_id) - will be claimed in process
        OT.info "[AddDomain] Found orphaned domain, will claim: #{@display_domain}"
        # Don't raise an error - let the process method claim it
      end

      def process
        # Check custom domains entitlement before creation
        # Only enforce when billing is enabled and entitlements are configured
        # (can?() returns true in standalone mode, false when plan has no entitlements)
        if organization.respond_to?(:can?) &&
           organization.entitlements.any? &&
           !organization.can?('custom_domains')
          raise_form_error('Upgrade required for custom domains', field: :domain, error_type: :upgrade_required)
        end

        @greenlighted  = true
        OT.ld "[AddDomain] Processing #{@display_domain}"

        @custom_domain = Onetime::CustomDomain.create!(@display_domain, organization.objid)

        begin
          # Request certificate using the configured strategy
          # This delegates to the appropriate backend (Approximated, Caddy, passthrough, etc.)
          request_certificate
        rescue HTTParty::ResponseError => ex
          OT.le format('[AddDomain.request_certificate error] %s %s %s', @cust.custid, @display_domain, ex)
          # Continue processing despite certificate request error
        rescue StandardError => ex
          OT.le "[AddDomain] Unexpected error: #{ex.message}"
          # Continue processing despite error
        end

        success_data
      end

      def request_certificate
        strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)
        result   = strategy.request_certificate(@custom_domain)

        OT.info "[AddDomain.request_certificate] #{@display_domain} -> #{result[:status]}"

        # Store the result data if available (for strategies like Approximated)
        if result[:data]
          @custom_domain.vhost   = result[:data].to_json
          @custom_domain.updated = OT.now.to_i
          @custom_domain.save
        end

        result
      end

      # Legacy method for backward compatibility
      # @deprecated Use request_certificate instead
      def create_vhost
        request_certificate
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
