# lib/onetime/domain_validation/caddy_on_demand_strategy.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    # CaddyOnDemandStrategy - Caddy's on_demand_tls certificate management.
    #
    # Use this when using Caddy's on-demand TLS feature. Caddy will call
    # the internal ACME endpoint to check if a domain is allowed before
    # issuing a certificate.
    #
    # This strategy doesn't perform validation itself - it relies on Caddy
    # to handle the ACME challenge and certificate issuance. We just track
    # which domains are registered in our system.
    #
    class CaddyOnDemandStrategy < BaseStrategy
      attr_reader :config

      def initialize(config)
        @config = config
      end

      # Validation delegated to Caddy's ACME challenge.
      #
      # @param _custom_domain [Onetime::CustomDomain] Ignored
      # @return [Hash] Delegated validation response
      #
      def validate_ownership(_custom_domain)
        {
          validated: true,
          message: 'Validation delegated to Caddy on-demand TLS',
          mode: 'caddy_on_demand',
        }
      end

      # Certificate issuance handled automatically by Caddy.
      #
      # @param _custom_domain [Onetime::CustomDomain] Ignored
      # @return [Hash] Delegated certificate response
      #
      def request_certificate(_custom_domain)
        {
          status: 'delegated',
          message: 'Certificate issuance delegated to Caddy',
          mode: 'caddy_on_demand',
        }
      end

      # Returns basic status - Caddy manages the actual certificate state.
      #
      # @param _custom_domain [Onetime::CustomDomain] Ignored
      # @return [Hash] Basic status (SSL state unknown)
      #
      def check_status(_custom_domain)
        {
          ready: true,
          message: 'Domain registered for Caddy on-demand TLS',
          mode: 'caddy_on_demand',
          has_ssl: nil, # Unknown - managed by Caddy
          is_resolving: nil, # Unknown - managed by Caddy
        }
      end

      # No-op for Caddy - certificate lifecycle managed by Caddy.
      #
      # @param _custom_domain [Onetime::CustomDomain] Ignored
      # @return [Hash] No-op response
      #
      def delete_vhost(_custom_domain)
        {
          deleted: false,
          message: 'No-op: certificate lifecycle managed by Caddy',
          mode: 'caddy_on_demand',
        }
      end

      # DNS widget not available for Caddy strategy.
      #
      # @return [Hash] Unavailable response
      #
      def get_dns_widget_token
        {
          available: false,
          message: 'DNS widget not available with Caddy on-demand TLS',
          mode: 'caddy_on_demand',
        }
      end

      # @return [Boolean] false - Caddy does not support DNS widget
      def supports_dns_widget?
        false
      end

      # @return [Boolean] false - Caddy manages certificates, not this strategy
      def manages_certificates?
        false
      end
    end
  end
end
