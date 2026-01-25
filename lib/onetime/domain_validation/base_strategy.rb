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
    #   | CaddyOnDemand   | passive  | auto | basic  | no-op  | no     |
    #   | Passthrough     | passive  | ext  | basic  | no-op  | no     |
    #
    class BaseStrategy
      # Validates domain ownership (typically via DNS TXT record).
      #
      # @param custom_domain [Onetime::CustomDomain] The domain to validate
      # @return [Hash] Validation result:
      #   - :validated [Boolean] Whether validation passed
      #   - :message [String] Human-readable result
      #   - :data [Hash, nil] Additional validation data (strategy-specific)
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
      #   - :has_ssl [Boolean, nil] SSL certificate status
      #   - :is_resolving [Boolean, nil] DNS resolution status
      #   - :status [String, nil] Provider-specific status code
      #   - :status_message [String, nil] Human-readable status
      #   - :data [Hash, nil] Full provider response (strategy-specific)
      #   - :mode [String, nil] Strategy mode identifier
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
    end
  end
end
