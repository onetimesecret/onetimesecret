# lib/onetime/domain_validation/caddy_on_demand_strategy.rb
#
# frozen_string_literal: true

require_relative 'txt_verifier'

module Onetime
  module DomainValidation
    # CaddyOnDemandStrategy - Caddy's on_demand_tls certificate management.
    #
    # Use this when using Caddy's on-demand TLS feature. Caddy calls the
    # internal ACME endpoint (apps/internal/acme) to ask whether a domain is
    # allowed before issuing a certificate, and that endpoint answers from
    # CustomDomain#ready?, which requires `verified`.
    #
    # Two separate proofs are involved and only one of them is Caddy's:
    #
    #   - Ownership: this strategy checks the TXT challenge record with our
    #     own DNS lookup (TxtVerifier), the same "exactly one matching value"
    #     rule the Approximated strategy applies.
    #   - Certificate issuance: Caddy completes the ACME challenge. That shows
    #     the name currently resolves to this deployment. It says nothing
    #     about which account, if any, controls the domain, so it is never
    #     read as ownership (ADR-016).
    #
    class CaddyOnDemandStrategy < BaseStrategy
      MODE = 'caddy_on_demand'

      attr_reader :config, :txt_verifier

      # @param config [Hash] Application configuration (typically OT.conf)
      # @param txt_verifier [#verify] Ownership checker (default: TxtVerifier).
      #   Injected so specs never touch the network.
      #
      def initialize(config, txt_verifier: TxtVerifier.new)
        @config       = config
        @txt_verifier = txt_verifier
      end

      # Validates domain ownership via the TXT challenge record.
      #
      # Three outcomes, passed through from TxtVerifier unchanged:
      #
      #   validated: true   exactly one TXT value, equal to the challenge
      #   validated: false  the resolver stated the record is missing or
      #                     different (demotes a verified domain, unless an
      #                     operator override holds it)
      #   validated: nil    the lookup produced no answer; stored state is
      #                     left alone (VerifyDomain#persist_changes)
      #
      # A domain with no challenge value also fails. TxtVerifier omits :data
      # for that case, but the :mode added here means VerifyDomain stores the
      # false: a domain with nothing to prove ownership is not verified.
      #
      # @param custom_domain [Onetime::CustomDomain]
      # @return [Hash] See BaseStrategy#validate_ownership
      #
      def validate_ownership(custom_domain)
        txt_verifier
          .verify(custom_domain.validation_record, custom_domain.txt_validation_value)
          .merge(mode: MODE)
      rescue StandardError => ex
        # TxtVerifier rescues its own lookup. Anything reaching here is ours
        # (e.g. the domain could not produce its validation record), which is
        # not evidence about the customer's DNS.
        OT.le "[CaddyOnDemandStrategy] Error validating #{custom_domain.display_domain}: " \
              "#{ex.class}: #{ex.message}"
        { validated: nil, indeterminate: true, message: "Error: #{ex.message}", mode: MODE }
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
          mode: MODE,
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
          mode: MODE,
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
          mode: MODE,
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
          mode: MODE,
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
