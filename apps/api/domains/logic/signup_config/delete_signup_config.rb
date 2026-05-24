# apps/api/domains/logic/signup_config/delete_signup_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signup_config'
require_relative 'base'

module DomainsAPI
  module Logic
    module SignupConfig
      # Delete Domain Signup Configuration
      #
      # @api Removes the signup validation configuration for a custom domain.
      #   Requires the requesting user to be an organization owner with
      #   custom_signup_validation entitlement.
      #
      # After deletion, signup on this domain falls back to global
      # allowed_signup_domains configuration.
      #
      class DeleteSignupConfig < Base
        attr_reader :deleted_strategy

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_signup_config!(@domain_id)

          # Verify config exists and capture strategy for audit
          existing_config = Onetime::CustomDomain::SignupConfig.find_by_domain_id(@custom_domain.identifier)
          unless existing_config
            raise_not_found("Signup configuration not found for domain: #{@domain_id}")
          end

          @deleted_strategy = existing_config.validation_strategy
        end

        def process
          OT.ld "[DeleteSignupConfig] Deleting signup config for domain #{@domain_id} by user #{cust.extid}"

          Onetime::CustomDomain::SignupConfig.delete_for_domain!(@custom_domain.identifier)

          success_data
        end

        def success_data
          {
            success: true,
            message: "Signup configuration deleted for domain #{@custom_domain.display_domain}",
          }
        end

        def form_fields
          {
            domain_id: @domain_id,
          }
        end
      end
    end
  end
end
