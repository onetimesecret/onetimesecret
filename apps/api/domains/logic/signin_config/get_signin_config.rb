# apps/api/domains/logic/signin_config/get_signin_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signin_config'
require_relative 'base'

module DomainsAPI
  module Logic
    module SigninConfig
      # Get Domain Signin Configuration
      #
      # @api Retrieves the sign-in method configuration for a custom domain.
      #   Requires the requesting user to be an organization owner with
      #   custom_signin_config entitlement.
      #
      # Response includes:
      # - enabled: Whether per-domain signin config is active
      # - signin_enabled: Boolean override for AUTH_SIGNIN
      # - restrict_to: Nullable restriction to a single auth method
      # - email_auth_enabled: Boolean override for email auth
      # - sso_enabled: Boolean override for SSO
      # - created_at: Unix timestamp
      # - updated_at: Unix timestamp
      #
      class GetSigninConfig < Base
        attr_reader :signin_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_signin_config!(@domain_id)

          @signin_config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@custom_domain.identifier)
          raise_not_found("Signin configuration not found for domain: #{@domain_id}") if @signin_config.nil?
        end

        def process
          OT.ld "[GetSigninConfig] Getting signin config for domain #{@domain_id} by user #{cust.extid}"

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_signin_config(@signin_config),
          }
        end

        private

        def serialize_signin_config(config)
          {
            domain_id: @custom_domain.extid,
            enabled: config.enabled?,
            signin_enabled: config.signin_enabled?,
            restrict_to: config.restrict_to,
            email_auth_enabled: config.email_auth_enabled?,
            sso_enabled: config.sso_enabled?,
            created_at: config.created.to_i,
            updated_at: config.updated.to_i,
          }
        end
      end
    end
  end
end
