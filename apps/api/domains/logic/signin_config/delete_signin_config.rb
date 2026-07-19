# apps/api/domains/logic/signin_config/delete_signin_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signin_config'
require_relative 'base'
require_relative 'audit_logger'

module DomainsAPI
  module Logic
    module SigninConfig
      # Delete Domain Signin Configuration
      #
      # @api Removes the sign-in method configuration for a custom domain.
      #   Requires the requesting user to be an organization owner with
      #   custom_signin_config entitlement.
      #
      # After deletion, sign-in on this custom domain reverts to the
      # default-OFF opt-in posture (open only when tenant SSO is available).
      #
      class DeleteSigninConfig < Base
        include AuditLogger

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_domain_signin_config!(@domain_id)

          existing_config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@custom_domain.identifier)
          unless existing_config
            raise_not_found("Signin configuration not found for domain: #{@domain_id}")
          end
        end

        def process
          OT.ld "[DeleteSigninConfig] Deleting signin config for domain #{@domain_id} by user #{cust.extid}"

          deleted = Onetime::CustomDomain::SigninConfig.delete_for_domain!(@custom_domain.identifier)

          if deleted
            log_signin_audit_event(
              event: :domain_signin_config_deleted,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
            )
          end

          success_data
        end

        def success_data
          {
            success: true,
            message: "Signin configuration deleted for domain #{@custom_domain.display_domain}",
            # Post-delete resolution truth: no record, so the custom domain
            # reverts to default-OFF (unless tenant SSO keeps it open, #3814).
            # Serialized so the settings UI can re-render without a refetch (ADR-024).
            details: signin_override_details(nil, @custom_domain.identifier),
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
