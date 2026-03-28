# apps/api/domains/logic/sso_config/delete_sso_config.rb
#
# frozen_string_literal: true

require 'onetime/models/domain_sso_config'
require_relative 'base'
require_relative 'audit_logger'

module DomainsAPI
  module Logic
    module SsoConfig
      # Delete Domain SSO Configuration
      #
      # @api Removes the SSO configuration for a custom domain.
      #   Requires the requesting user to be an organization owner with manage_sso.
      #   Returns 200 with JSON confirmation on success.
      #
      # After deletion, users will no longer be able to authenticate via SSO
      # on this domain. They must use standard email/password authentication
      # or another configured method.
      #
      class DeleteSsoConfig < Base
        include AuditLogger

        attr_reader :deleted_provider_type

        def process_params
          @domain_id = sanitize_identifier(params['domain_id'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_domain_sso!(@domain_id)

          # Verify config exists and capture provider_type for audit
          existing_config = Onetime::DomainSsoConfig.find_by_domain_id(@custom_domain.identifier)
          unless existing_config
            raise_not_found("SSO configuration not found for domain: #{@domain_id}")
          end

          @deleted_provider_type = existing_config.provider_type
        end

        def process
          OT.ld "[DeleteSsoConfig] Deleting SSO config for domain #{@domain_id} by user #{cust.extid}"

          # Delete the config atomically
          deleted = Onetime::DomainSsoConfig.delete_for_domain!(@custom_domain.identifier)

          if deleted
            log_sso_audit_event(
              event: :domain_sso_config_deleted,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider_type: @deleted_provider_type,
            )
          end

          success_data
        end

        def success_data
          {
            success: true,
            message: "SSO configuration deleted for domain #{@custom_domain.display_domain}",
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
