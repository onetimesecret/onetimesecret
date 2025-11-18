# lib/onetime/domain_validation/passthrough_strategy.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    # Passthrough Strategy - No validation or certificate management
    #
    # Use this when your reverse proxy (Caddy, nginx, Traefik, etc.) handles
    # SSL certificates and validation automatically. The system just tracks
    # which domains are configured without interfering.
    #
    class PassthroughStrategy < BaseStrategy
      def initialize(config)
        @config = config
      end

      def validate_ownership(_custom_domain)
        {
          validated: true,
          message: 'External validation (passthrough mode)',
          mode: 'passthrough',
        }
      end

      def request_certificate(_custom_domain)
        {
          status: 'external',
          message: 'Certificate management handled externally',
          mode: 'passthrough',
        }
      end

      def check_status(_custom_domain)
        {
          ready: true,
          message: 'External management (passthrough mode)',
          mode: 'passthrough',
          has_ssl: true, # Assumed
          is_resolving: true, # Assumed
        }
      end
    end
  end
end
