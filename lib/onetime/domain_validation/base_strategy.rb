# lib/onetime/domain_validation/base_strategy.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    # Base strategy class - defines the interface all strategies must implement
    class BaseStrategy
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
    end
  end
end
