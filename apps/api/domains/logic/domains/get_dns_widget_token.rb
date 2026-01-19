# apps/api/domains/logic/domains/get_dns_widget_token.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/strategy'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    # Returns a DNS widget token for client-side DNS record management.
    #
    # The Approximated DNS widget helps users configure their DNS records
    # by detecting their DNS provider and offering automated updates or
    # provider-specific instructions.
    #
    # Tokens expire after 10 minutes but the widget auto-renews them.
    #
    # This endpoint only returns tokens when using the Approximated strategy.
    # Other strategies (passthrough, caddy_on_demand) return unavailable.
    #
    class GetDnsWidgetToken < DomainsAPI::Logic::Base
      def process_params
        # No params needed - token is generated for the authenticated user
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error 'Authentication required' unless @cust

        # Require organization context for domain management
        require_organization!

        # Check if strategy supports DNS widget
        @strategy = Onetime::DomainValidation::Strategy.for_config(OT.conf)
        unless @strategy.supports_dns_widget?
          raise_form_error 'DNS widget not available'
        end
      end

      def process
        result = @strategy.get_dns_widget_token

        if result[:available]
          {
            success: true,
            token: result[:token],
            api_url: result[:api_url],
            expires_in: result[:expires_in],
          }
        else
          raise_form_error result[:message] || 'Failed to generate DNS widget token'
        end
      end
    end
  end
end
