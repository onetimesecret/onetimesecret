# lib/onetime/domain_validation/strategy.rb
#
# frozen_string_literal: true
#
# Domain Validation Strategy Pattern
#
# Provides an abstraction layer for different domain validation and certificate
# management approaches. This allows the system to work with various backends:
# - Approximated (custom-domains-as-a-service)
# - Caddy on-demand TLS
# - External/manual certificate management
# - Custom implementations
#
# Usage:
#   strategy = Onetime::DomainValidation::Strategy.for_config(config)
#   result = strategy.validate_ownership(custom_domain)
#   cert_status = strategy.request_certificate(custom_domain)
#

module Onetime
  module DomainValidation
    # Base strategy class - defines the interface all strategies must implement
    class Strategy
      # Validates domain ownership (typically via DNS TXT record)
      #
      # @param custom_domain [Onetime::CustomDomain] The domain to validate
      # @return [Hash] Validation result with :validated (boolean) and :message (string)
      def validate_ownership(custom_domain)
        raise NotImplementedError, "#{self.class} must implement #validate_ownership"
      end

      # Requests SSL certificate for the domain
      #
      # @param custom_domain [Onetime::CustomDomain] The domain needing a certificate
      # @return [Hash] Certificate request result with :status and optional :data
      def request_certificate(custom_domain)
        raise NotImplementedError, "#{self.class} must implement #request_certificate"
      end

      # Checks the current status of domain validation and certificate
      #
      # @param custom_domain [Onetime::CustomDomain] The domain to check
      # @return [Hash] Status with :ready (boolean), :has_ssl, :is_resolving, etc.
      def check_status(custom_domain)
        raise NotImplementedError, "#{self.class} must implement #check_status"
      end

      # Factory method to create appropriate strategy based on configuration
      #
      # @param config [Hash] Configuration hash from OT.conf
      # @return [Strategy] Appropriate strategy instance
      def self.for_config(config)
        strategy_name = config.dig('site', 'domains', 'strategy')&.to_s || 'approximated'

        case strategy_name.downcase
        when 'approximated'
          ApproximatedStrategy.new(config)
        when 'passthrough', 'external'
          PassthroughStrategy.new(config)
        when 'caddy_on_demand', 'caddy'
          CaddyOnDemandStrategy.new(config)
        else
          OT.le "[DomainValidation] Unknown strategy: #{strategy_name}, defaulting to passthrough"
          PassthroughStrategy.new(config)
        end
      end
    end

    # Approximated Strategy - Uses approximated.app API for validation and certs
    #
    # This is the original implementation that delegates to an external service
    # for SSL certificate provisioning and DNS validation.
    #
    class ApproximatedStrategy < Strategy
      def initialize(config)
        @config = config
        require 'onetime/cluster'
      end

      def validate_ownership(custom_domain)
        api_key = Onetime::Cluster::Features.api_key

        if api_key.to_s.empty?
          return { validated: false, message: 'Approximated API key not configured' }
        end

        records = [{
          type: 'TXT',
          address: custom_domain.validation_record,
          match_against: custom_domain.txt_validation_value,
        }]

        res = Onetime::Cluster::Approximated.check_records_match_exactly(api_key, records)

        if res.code == 200
          payload = res.parsed_response
          match_records = payload['records']
          found_match = match_records.any? { |record| record['match'] == true }

          {
            validated: found_match,
            message: found_match ? 'TXT record validated' : 'TXT record not found or mismatch',
            data: match_records
          }
        else
          {
            validated: false,
            message: "Validation check failed: #{res.code}",
            error: res.parsed_response
          }
        end
      rescue StandardError => e
        OT.le "[ApproximatedStrategy] Error validating #{custom_domain.display_domain}: #{e.message}"
        { validated: false, message: "Error: #{e.message}" }
      end

      def request_certificate(custom_domain)
        api_key = Onetime::Cluster::Features.api_key
        vhost_target = Onetime::Cluster::Features.vhost_target

        if api_key.to_s.empty?
          return { status: 'error', message: 'Approximated API key not configured' }
        end

        res = Onetime::Cluster::Approximated.create_vhost(
          api_key,
          custom_domain.display_domain,
          vhost_target,
          '443'
        )

        if res.code == 200
          payload = res.parsed_response
          {
            status: 'requested',
            message: 'Virtual host created',
            data: payload['data']
          }
        else
          {
            status: 'error',
            message: "Failed to create vhost: #{res.code}",
            error: res.parsed_response
          }
        end
      rescue HTTParty::ResponseError => e
        OT.le "[ApproximatedStrategy] Error requesting cert for #{custom_domain.display_domain}: #{e.message}"
        { status: 'error', message: "Error: #{e.message}" }
      end

      def check_status(custom_domain)
        api_key = Onetime::Cluster::Features.api_key

        if api_key.to_s.empty?
          return { ready: false, message: 'Approximated API key not configured' }
        end

        res = Onetime::Cluster::Approximated.get_vhost_by_incoming_address(
          api_key,
          custom_domain.display_domain
        )

        if res.code == 200
          payload = res.parsed_response
          data = payload['data']

          {
            ready: data['status'] == 'ACTIVE_SSL',
            has_ssl: data['has_ssl'],
            is_resolving: data['is_resolving'],
            status: data['status'],
            status_message: data['status_message'],
            data: data
          }
        else
          {
            ready: false,
            message: "Status check failed: #{res.code}",
            error: res.parsed_response
          }
        end
      rescue HTTParty::ResponseError => e
        OT.le "[ApproximatedStrategy] Error checking status for #{custom_domain.display_domain}: #{e.message}"
        { ready: false, message: "Error: #{e.message}" }
      end
    end

    # Passthrough Strategy - No validation or certificate management
    #
    # Use this when your reverse proxy (Caddy, nginx, Traefik, etc.) handles
    # SSL certificates and validation automatically. The system just tracks
    # which domains are configured without interfering.
    #
    class PassthroughStrategy < Strategy
      def initialize(config)
        @config = config
      end

      def validate_ownership(custom_domain)
        {
          validated: true,
          message: 'External validation (passthrough mode)',
          mode: 'passthrough'
        }
      end

      def request_certificate(custom_domain)
        {
          status: 'external',
          message: 'Certificate management handled externally',
          mode: 'passthrough'
        }
      end

      def check_status(custom_domain)
        {
          ready: true,
          message: 'External management (passthrough mode)',
          mode: 'passthrough',
          has_ssl: true, # Assumed
          is_resolving: true # Assumed
        }
      end
    end

    # Caddy On-Demand TLS Strategy
    #
    # Use this when using Caddy's on_demand_tls feature. Caddy will call
    # the internal ACME endpoint to check if a domain is allowed before
    # issuing a certificate.
    #
    # This strategy doesn't perform validation itself - it relies on Caddy
    # to handle the ACME challenge and certificate issuance. We just track
    # which domains are registered in our system.
    #
    class CaddyOnDemandStrategy < Strategy
      def initialize(config)
        @config = config
      end

      def validate_ownership(custom_domain)
        # With Caddy on-demand, we don't validate ownership ourselves.
        # Caddy will perform the ACME challenge when it receives a TLS request.
        {
          validated: true,
          message: 'Validation delegated to Caddy on-demand TLS',
          mode: 'caddy_on_demand'
        }
      end

      def request_certificate(custom_domain)
        # Caddy handles certificate requests automatically via on-demand TLS
        {
          status: 'delegated',
          message: 'Certificate issuance delegated to Caddy',
          mode: 'caddy_on_demand'
        }
      end

      def check_status(custom_domain)
        # We can't easily check Caddy's certificate status from here,
        # so we just report that the domain is ready if it's in our database
        {
          ready: true,
          message: 'Domain registered for Caddy on-demand TLS',
          mode: 'caddy_on_demand',
          has_ssl: nil, # Unknown - managed by Caddy
          is_resolving: nil # Unknown - managed by Caddy
        }
      end
    end
  end
end
