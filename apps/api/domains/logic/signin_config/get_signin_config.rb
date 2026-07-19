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
      # - record: the raw flag pair + overrides, or null when the domain is
      #   unconfigured. Unconfigured is a first-class state (200, not 404) so
      #   the settings UI can render the inherited global state (ADR-024).
      # - details: global_enabled / effective_enabled / global_restrict_to —
      #   the resolver's output, which the UI displays instead of re-deriving.
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
        end

        def process
          OT.ld "[GetSigninConfig] Getting signin config for domain #{@domain_id} by user #{cust.extid}"

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: @signin_config.nil? ? nil : serialize_signin_config(@signin_config),
            details: signin_override_details(@signin_config, @custom_domain.identifier),
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
