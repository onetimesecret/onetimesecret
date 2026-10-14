# apps/api/domains/logic/sender_config/delete_sender_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require 'onetime/operations/delete_sender_domain'
require_relative 'base'
require_relative 'change_logger'

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
        include ChangeLogger

        attr_reader :deleted_provider

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          # Require authenticated user
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?

          # Validate domain_id parameter
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          # Load domain and organization, verify ownership and entitlement
          authorize_sender_config!(@domain_id)

          # Verify config exists
          return if Onetime::CustomDomain::MailerConfig.exists_for_domain?(@custom_domain.identifier)

          raise_not_found("Sender configuration not found for domain: #{@domain_id}")
        end

        def process
          OT.ld "[DeleteSenderConfig] Deleting sender config for domain #{@domain_id} by user #{cust.extid}"

          # Remove the record first and tear down the provider identity it
          # held: of concurrent deletes only one gets the record
          # (GuardedConfigWrites#remove_for_domain!), so the provider call and
          # the audit event happen once and describe what was deleted.
          # DeleteSenderDomain never raises and reads only the record passed in.
          deleted = guarded_config_write do
            Onetime::CustomDomain::MailerConfig.remove_for_domain!(@custom_domain.identifier)
          end

          if deleted
            @deleted_provider = deleted.provider
            delete_sender_domain(deleted)
            log_sender_config_event(
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

        private

        def delete_sender_domain(mailer_config)
          Onetime::Operations::DeleteSenderDomain.new(
            mailer_config: mailer_config,
          ).call
        end
      end
    end
  end
end
