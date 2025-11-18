# lib/onetime/domain_validation/caddy_on_demand_strategy.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
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
    class CaddyOnDemandStrategy < BaseStrategy
      def initialize(config)
        @config = config
      end

      def validate_ownership(_custom_domain)
        # With Caddy on-demand, we don't validate ownership ourselves.
        # Caddy will perform the ACME challenge when it receives a TLS request.
        {
          validated: true,
          message: 'Validation delegated to Caddy on-demand TLS',
          mode: 'caddy_on_demand',
        }
      end

      def request_certificate(_custom_domain)
        # Caddy handles certificate requests automatically via on-demand TLS
        {
          status: 'delegated',
          message: 'Certificate issuance delegated to Caddy',
          mode: 'caddy_on_demand',
        }
      end

      def check_status(_custom_domain)
        # We can't easily check Caddy's certificate status from here,
        # so we just report that the domain is ready if it's in our database
        {
          ready: true,
          message: 'Domain registered for Caddy on-demand TLS',
          mode: 'caddy_on_demand',
          has_ssl: nil, # Unknown - managed by Caddy
          is_resolving: nil, # Unknown - managed by Caddy
        }
      end
    end
  end
end
