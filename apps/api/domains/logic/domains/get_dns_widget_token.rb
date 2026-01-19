# apps/api/domains/logic/domains/get_dns_widget_token.rb
#
# frozen_string_literal: true

require 'onetime/cluster'
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
    class GetDnsWidgetToken < DomainsAPI::Logic::Base
      def process_params
        # No params needed - token is generated for the authenticated user
      end

      def raise_concerns
        # Require authenticated user
        raise_form_error 'Authentication required' unless @cust

        # Require organization context for domain management
        require_organization!

        # Verify Approximated API is configured
        api_key = Onetime::Cluster::Features.api_key
        if api_key.to_s.empty?
          raise_form_error 'DNS widget not available'
        end
      end

      def process
        api_key = Onetime::Cluster::Features.api_key

        begin
          response = Onetime::Cluster::Approximated.get_dns_widget_token(api_key)

          if response.code == 200
            {
              success: true,
              token: response.parsed_response['token'],
              api_url: 'https://cloud.approximated.app/api/dns',
              expires_in: 600, # 10 minutes
            }
          else
            raise_form_error 'Failed to generate DNS widget token'
          end
        rescue HTTParty::ResponseError => ex
          OT.le "[GetDnsWidgetToken] API error: #{ex.message}"
          raise_form_error 'DNS widget temporarily unavailable'
        end
      end
    end
  end
end
