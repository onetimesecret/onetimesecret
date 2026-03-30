# apps/api/domains/logic/sender_config/validate_sender_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require 'onetime/jobs/publisher'
require_relative 'base'
require_relative 'serializers'
require_relative 'audit_logger'

module DomainsAPI
  module Logic
    module SenderConfig
      # POST Domain Sender DNS Validation (async)
      #
      # Triggers DNS record verification for a custom domain's mail sender
      # configuration. Sets verification_status to 'pending' and enqueues
      # a background job for the actual DNS lookups.
      #
      # The caller can poll GET /:extid/email-config to observe the status
      # transition from 'pending' to 'verified' or 'failed'.
      #
      # Requires the requesting user to be an organization owner with
      # custom_mail_sender entitlement.
      #
      class ValidateSenderConfig < Base
        include Serializers
        include AuditLogger

        attr_reader :mailer_config

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :unauthorized) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_sender_config!(@domain_id)

          @mailer_config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@custom_domain.identifier)
          raise_form_error('No sender configuration found for this domain', field: :domain_id, error_type: :missing) unless @mailer_config

          # Require a provider and from_address before validation makes sense
          if @mailer_config.provider.to_s.empty? || @mailer_config.from_address.to_s.empty?
            raise_form_error('Sender configuration must have provider and from_address before validation', field: :provider, error_type: :missing)
          end
        end

        def process
          OT.ld "[ValidateSenderConfig] Triggering async DNS validation for domain #{@domain_id} by user #{cust.extid}"

          # Set status to pending before enqueuing so the UI reflects immediately
          previous_status                    = @mailer_config.verification_status
          @mailer_config.verification_status = VERIFICATION_STATUS_PENDING
          @mailer_config.updated             = Familia.now.to_i
          @mailer_config.save_fields(:verification_status, :updated)

          # Enqueue background validation job
          begin
            Onetime::Jobs::Publisher.enqueue_domain_validation(@custom_domain.identifier)
          rescue StandardError
            # Rollback: restore previous status so it doesn't stay stuck in 'pending'
            @mailer_config.verification_status = previous_status
            @mailer_config.updated             = Familia.now.to_i
            @mailer_config.save_fields(:verification_status, :updated)
            raise
          end

          log_sender_audit_event(
            event: :domain_sender_validation_requested,
            domain: @custom_domain,
            org: @organization,
            actor: cust,
            provider: @mailer_config.provider,
          )

          success_data
        end

        def success_data
          {
            user_id: cust.extid,
            record: serialize_sender_config(@mailer_config),
            message: 'DNS validation initiated. Poll GET email-config for status updates.',
          }
        end

        def form_fields
          { domain_id: @domain_id }
        end
      end
    end
  end
end
