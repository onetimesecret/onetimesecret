# apps/api/domains/logic/sender_config/delete_sender_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require_relative 'base'
require_relative 'audit_logger'

module DomainsAPI
  module Logic
    module SenderConfig
      # Delete Domain Sender Configuration
      #
      # @api Removes the mail sender configuration for a custom domain.
      #   Requires the requesting user to be an organization owner
      #   with custom_mail_sender entitlement.
      #   Returns 200 with JSON confirmation on success.
      #
      # After deletion, the domain will revert to the instance-level default
      # mail sender configuration.
      #
      class DeleteSenderConfig < Base
        include AuditLogger

        attr_reader :deleted_provider

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_sender_config!(@domain_id)

          # Verify config exists and capture provider for audit
          existing_config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@custom_domain.identifier)
          unless existing_config
            raise_not_found("Sender configuration not found for domain: #{@domain_id}")
          end

          @deleted_provider = existing_config.provider
        end

        def process
          OT.ld "[DeleteSenderConfig] Deleting sender config for domain #{@domain_id} by user #{cust.extid}"

          # Delete the config atomically
          deleted = Onetime::CustomDomain::MailerConfig.delete_for_domain!(@custom_domain.identifier)

          if deleted
            log_sender_audit_event(
              event: :domain_sender_config_deleted,
              domain: @custom_domain,
              org: @organization,
              actor: cust,
              provider: @deleted_provider,
            )
          end

          success_data
        end

        def success_data
          {
            success: true,
            message: "Sender configuration deleted for domain #{@custom_domain.display_domain}",
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
