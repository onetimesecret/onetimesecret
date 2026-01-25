# lib/onetime/domain_validation/passthrough_strategy.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    # PassthroughStrategy - No validation or certificate management.
    #
    # Use this when your reverse proxy (Caddy, nginx, Traefik, etc.) handles
    # SSL certificates and validation automatically. The system just tracks
    # which domains are configured without interfering.
    #
    # All operations return success/no-op responses since certificate
    # management is handled externally.
    #
    class PassthroughStrategy < BaseStrategy
      attr_reader :config

      def initialize(config)
        @config = config
      end

      # @param _custom_domain [Onetime::CustomDomain] Ignored
      # @return [Hash] Always returns validated: true
      #
      def validate_ownership(_custom_domain)
        {
          validated: true,
          message: 'External validation (passthrough mode)',
          mode: 'passthrough',
        }
      end

      # @param _custom_domain [Onetime::CustomDomain] Ignored
      # @return [Hash] Status indicating external management
      #
      def request_certificate(_custom_domain)
        {
          status: 'external',
          message: 'Certificate management handled externally',
          mode: 'passthrough',
        }
      end

      # @param _custom_domain [Onetime::CustomDomain] Ignored
      # @return [Hash] Assumed-ready status
      #
      def check_status(_custom_domain)
        {
          ready: true,
          message: 'External management (passthrough mode)',
          mode: 'passthrough',
          has_ssl: true, # Assumed - managed externally
          is_resolving: true, # Assumed - managed externally
        }
      end

      # No-op for passthrough - certificates managed externally.
      #
      # @param _custom_domain [Onetime::CustomDomain] Ignored
      # @return [Hash] No-op response
      #
      def delete_vhost(_custom_domain)
        {
          deleted: false,
          message: 'No-op: certificate management handled externally',
          mode: 'passthrough',
        }
      end

      # DNS widget not available for passthrough strategy.
      #
      # @return [Hash] Unavailable response
      #
      def get_dns_widget_token
        {
          available: false,
          message: 'DNS widget not available in passthrough mode',
          mode: 'passthrough',
        }
      end

      # @return [Boolean] false - passthrough does not support DNS widget
      def supports_dns_widget?
        false
      end

      # @return [Boolean] false - passthrough does not manage certificates
      def manages_certificates?
        false
      end
    end
  end
end
