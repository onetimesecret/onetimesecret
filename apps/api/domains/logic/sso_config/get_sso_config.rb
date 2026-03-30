# apps/api/domains/logic/sso_config/get_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/sso_config'
require_relative 'base'
require_relative 'serializers'

module DomainsAPI
  module Logic
    module SsoConfig
      # Get Domain SSO Configuration
      #
      # @api Retrieves the SSO configuration for a custom domain.
      #   Returns the config with masked client_secret (only last 4 chars visible).
      #   Requires the requesting user to be an organization owner with manage_sso.
      #
      # Response includes:
      # - provider_type: oidc, entra_id, google, github
      # - client_id: Full client ID (not sensitive)
      # - client_secret_masked: Masked (e.g., "••••••••abcd")
      # - tenant_id: For Entra ID
      # - issuer: For OIDC
      # - display_name: Human-readable name
      # - allowed_domains: Array of allowed email domains
      # - enabled: Whether SSO is active
      # - created_at: Unix timestamp
      # - updated_at: Unix timestamp
      #
      class GetSsoConfig < Base
        include Serializers

        attr_reader :sso_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_sso!(@domain_id)

          # Load SSO config
          @sso_config = Onetime::CustomDomain::SsoConfig.find_by_domain_id(@custom_domain.identifier)
          raise_not_found("SSO configuration not found for domain: #{@domain_id}") if @sso_config.nil?
        end

        def process
          OT.ld "[GetSsoConfig] Getting SSO config for domain #{@domain_id} by user #{cust.extid}"

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_sso_config(@sso_config),
          }
        end
      end
    end
  end
end
