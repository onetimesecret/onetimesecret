# apps/api/domains/logic/sso_config/token_endpoint_auth_method_report.rb
#
# frozen_string_literal: true

module DomainsAPI
  module Logic
    module SsoConfig
      # Test Connection's advisory on the selected token_endpoint_auth_method
      # (#4764). Reads @provider_type and @token_endpoint_auth_method from the
      # including logic class.
      module TokenEndpointAuthMethodReport
        # OIDC Discovery 1.0 section 3: when a document omits
        # token_endpoint_auth_methods_supported, the default is
        # client_secret_basic.
        DEFAULT_TOKEN_ENDPOINT_AUTH_METHODS = %w[client_secret_basic].freeze

        private

        # Whether the IdP advertises the selected token_endpoint_auth_method
        # (#4764). Advisory, never a failure: an IdP may accept a method it
        # does not list, and the gem default is the IdP's own default.
        #
        #   token_endpoint_auth_methods_supported — the document's list, or
        #     nil when it omits the field
        #   token_endpoint_auth_method_supported  — true/false against that
        #     list (defaulted per OIDC Discovery 1.0 section 3), nil when
        #     nothing is selected
        #   note — only when selected and not advertised
        #
        # @param discovery [Hash] parsed discovery document
        # @return [Hash]
        def token_endpoint_auth_method_details(discovery)
          advertised = discovery['token_endpoint_auth_methods_supported']
          advertised = nil unless advertised.is_a?(Array)
          advertised = advertised&.map(&:to_s)
          selected   = @provider_type == 'oidc' ? @token_endpoint_auth_method.to_s : ''
          details    = { token_endpoint_auth_methods_supported: advertised }

          if selected.empty?
            return details.merge(token_endpoint_auth_method_supported: nil)
          end

          supported = (advertised || DEFAULT_TOKEN_ENDPOINT_AUTH_METHODS).include?(selected)

          details[:token_endpoint_auth_method_supported] = supported
          return details if supported

          advertised_text = if advertised.nil?
                              "none (the OIDC Discovery default is #{DEFAULT_TOKEN_ENDPOINT_AUTH_METHODS.join(', ')})"
                            elsif advertised.empty?
                              'an empty list'
                            else
                              advertised.join(', ')
                            end

          details[:note] = "The IdP does not advertise #{selected} in token_endpoint_auth_methods_supported " \
                           "(advertised: #{advertised_text}). Sign-in may still work; if the token exchange " \
                           'fails, choose an advertised method.'
          details
        end
      end
    end
  end
end
