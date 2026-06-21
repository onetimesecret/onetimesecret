# apps/api/domains/logic/signup_config/get_signup_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signup_config'
require_relative 'base'

module DomainsAPI
  module Logic
    module SignupConfig
      # Get Domain Signup Configuration
      #
      # @api Retrieves the signup validation configuration for a custom domain.
      #   Requires the requesting user to be an organization owner with
      #   custom_signup_validation entitlement.
      #
      # Response includes:
      # - validation_strategy: passthrough, domain_allowlist, mx, smtp
      # - allowed_signup_domains: Array of allowed email domains (for domain_allowlist)
      # - enabled: Whether per-domain validation is active
      # - created_at: Unix timestamp
      # - updated_at: Unix timestamp
      #
      class GetSignupConfig < Base
        attr_reader :signup_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_signup_config!(@domain_id)

          # Load signup config
          @signup_config = Onetime::CustomDomain::SignupConfig.find_by_domain_id(@custom_domain.identifier)
          raise_not_found("Signup configuration not found for domain: #{@domain_id}") if @signup_config.nil?
        end

        def process
          OT.ld "[GetSignupConfig] Getting signup config for domain #{@domain_id} by user #{cust.extid}"

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_signup_config(@signup_config),
          }
        end

        private

        def serialize_signup_config(config)
          {
            domain_id: @custom_domain.extid,
            validation_strategy: config.validation_strategy,
            allowed_signup_domains: config.allowed_signup_domains,
            enabled: config.enabled?,
            signup_enabled: config.signup_enabled?,
            autoverify: config.autoverify?,
            requires_allowlist: config.requires_allowlist?,
            network_validation: config.network_validation?,
            created_at: config.created.to_i,
            updated_at: config.updated.to_i,
          }
        end
      end
    end
  end
end
