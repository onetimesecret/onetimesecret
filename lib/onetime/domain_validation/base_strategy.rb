# lib/onetime/domain_validation/base_strategy.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    # BaseStrategy - Interface for domain validation strategies.
    #
    # All strategies must implement these methods. The interface supports
    # three tiers of functionality:
    #
    # 1. Core (required for all strategies):
    #    - validate_ownership: DNS TXT record validation
    #    - request_certificate: SSL certificate provisioning
    #    - check_status: Current domain/SSL status
    #
    # 2. Management (optional, returns no-op for passive strategies):
    #    - delete_vhost: Remove domain from SSL provider
    #
    # 3. Client Support (optional, returns unavailable for passive strategies):
    #    - get_dns_widget_token: Token for DNS management widget
    #
    # Strategy Capabilities:
    #
    #   | Strategy        | validate | cert | status | delete | widget |
    #   |-----------------|----------|------|--------|--------|--------|
    #   | Approximated    | active   | yes  | yes    | yes    | yes    |
    #   | CaddyOnDemand   | active   | auto | probe  | no-op  | no     |
    #   | Passthrough     | passive  | ext  | basic  | no-op  | no     |
    #
    # "active" validate means the strategy checks the TXT challenge record:
    # Approximated through its API with a native fallback, CaddyOnDemand with
    # our own DNS lookup (TxtVerifier). Caddy obtaining a certificate is not
    # an ownership check; it only shows where the name resolves.
    #
    # "probe" status means CaddyOnDemand works it out on the network itself
    # (TlsProbe: our own A/AAAA lookup and a verified TLS handshake on port
    # 443, through the egress guard), with nil for "could not tell".
    # Passthrough's "basic" is a constant answer with no network activity.
    #
    class BaseStrategy
      # Validates domain ownership (typically via DNS TXT record).
      #
      # @param custom_domain [Onetime::CustomDomain] The domain to validate
      # @return [Hash] Validation result:
      #   - :validated [Boolean, nil] Whether validation passed; nil when the
      #     check could not produce an answer (indeterminate). Callers must
      #     not change stored verification state on nil.
      #   - :indeterminate [Boolean, nil] true alongside validated: nil
      #   - :message [String] Human-readable result
      #   - :data [Array, Hash, nil] Additional validation data
      #     (strategy-specific). VerifyDomain only changes stored state for a
      #     result that carries :data or :mode.
      #   - :source [String, nil] 'native' when our own DNS lookup decided
      #   - :mode [String, nil] Strategy mode identifier
      #
      def validate_ownership(custom_domain)
        raise NotImplementedError, "#{self.class} must implement #validate_ownership"
      end

      # Requests SSL certificate for the domain.
      #
      # @param custom_domain [Onetime::CustomDomain] The domain needing a certificate
      # @return [Hash] Certificate request result:
      #   - :status [String] 'requested', 'delegated', 'external', 'error'
      #   - :message [String] Human-readable result
      #   - :data [Hash, nil] Vhost/certificate data (strategy-specific)
      #   - :mode [String, nil] Strategy mode identifier
      #
      def request_certificate(custom_domain)
        raise NotImplementedError, "#{self.class} must implement #request_certificate"
      end

      # Checks the current status of domain validation and certificate.
      #
      # @param custom_domain [Onetime::CustomDomain] The domain to check
      # @return [Hash] Status information:
      #   - :ready [Boolean] Whether domain is fully operational
      #   - :has_ssl [Boolean, nil] SSL certificate status; nil = could not tell
      #   - :is_resolving [Boolean, nil] DNS resolution status; nil = could not
      #     tell, and the stored `resolving` flag is left alone
      #   - :status [String, nil] Provider-specific status code
      #   - :status_message [String, nil] Human-readable status
      #   - :data [Hash, nil] Payload stored as the domain's `vhost` blob, which
      #     is where has_ssl is kept. Leave it out when has_ssl is nil so the
      #     stored value is not overwritten.
      #   - :mode [String, nil] Strategy mode identifier
      #
      # Returning neither :data nor :mode means the check itself failed:
      # VerifyDomain stores nothing and sets vhost_fetch_failed_at.
      #
      def check_status(custom_domain)
        raise NotImplementedError, "#{self.class} must implement #check_status"
      end

      # Deletes the vhost/certificate from the SSL provider.
      #
      # For active strategies (Approximated), this removes the domain
      # from the external SSL provider. For passive strategies, this
      # is a no-op since certificate management is external.
      #
      # @param custom_domain [Onetime::CustomDomain] The domain to remove
      # @return [Hash] Deletion result:
      #   - :deleted [Boolean] Whether deletion was performed
      #   - :message [String] Human-readable result
      #   - :mode [String, nil] Strategy mode identifier
      #
      def delete_vhost(custom_domain)
        raise NotImplementedError, "#{self.class} must implement #delete_vhost"
      end

      # Retrieves a DNS widget token for client-side DNS management.
      #
      # Only supported by Approximated strategy. Other strategies return
      # an unavailable response.
      #
      # @return [Hash] Token result:
      #   - :available [Boolean] Whether widget is supported
      #   - :token [String, nil] Widget token (10 min expiry)
      #   - :api_url [String, nil] Widget API endpoint
      #   - :expires_in [Integer, nil] Token TTL in seconds
      #   - :message [String, nil] Status/error message
      #
      def get_dns_widget_token
        raise NotImplementedError, "#{self.class} must implement #get_dns_widget_token"
      end

      # Returns the strategy name for logging and debugging.
      #
      # @return [String] Strategy identifier
      #
      def strategy_name
        self.class.name.split('::').last.sub('Strategy', '').downcase
      end

      # Checks if this strategy supports active DNS widget functionality.
      #
      # @return [Boolean]
      #
      def supports_dns_widget?
        false
      end

      # Checks if this strategy actively manages vhosts/certificates.
      #
      # @return [Boolean]
      #
      def manages_certificates?
        false
      end

      # Seconds a bulk run should pause between domains for this strategy.
      #
      # Pacing belongs to whatever the strategy talks to: a provider API with
      # a request cap needs a pause, our own DNS and TLS lookups do not.
      # VerifyDomain's bulk mode uses this unless the caller passes an
      # explicit rate_limit.
      #
      # @return [Numeric] seconds; 0 means no pause
      #
      def bulk_rate_limit
        0
      end
    end
  end
end
