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

          # Require from_address before validation makes sense
          # (provider is resolved from installation-level configuration)
          if @mailer_config.from_address.to_s.empty?
            raise_form_error('Sender configuration must have from_address before validation', field: :from_address, error_type: :missing)
          end
        end

        def process
          OT.ld "[ValidateSenderConfig] Triggering async DNS validation for domain #{@domain_id} by user #{cust.extid}"

          # Acquire lock to prevent concurrent revalidation requests
          lock       = Familia::Lock.new("domain:#{@custom_domain.identifier}:revalidate")
          lock_token = lock.acquire(ttl: 60)
          raise_form_error('Validation already in progress. Please try again.', field: :domain_id, error_type: :conflict) unless lock_token

          begin
            # Capture previous values for rollback
            previous_status                      = @mailer_config.verification_status
            previous_dns_check_completed_at      = @mailer_config.dns_check_completed_at
            previous_provider_check_completed_at = @mailer_config.provider_check_completed_at

            # Set status to pending and clear completion timestamps so the UI reflects immediately
            @mailer_config.verification_status         = VERIFICATION_STATUS_PENDING
            @mailer_config.dns_check_completed_at      = ''
            @mailer_config.provider_check_completed_at = ''
            @mailer_config.updated                     = Familia.now.to_i
            @mailer_config.save_fields(:verification_status, :dns_check_completed_at, :provider_check_completed_at, :updated)

            # Enqueue both background validation jobs
            # (user explicitly requested fresh verification via "Verify Now")
            Onetime::Jobs::Publisher.enqueue_dns_record_check(@custom_domain.identifier)
            Onetime::Jobs::Publisher.enqueue_domain_validation(
              @custom_domain.identifier,
              bypass_cache: true,
            )
          rescue StandardError
            # Rollback: restore previous status and timestamps so nothing stays stuck in 'pending'
            @mailer_config.verification_status         = previous_status
            @mailer_config.dns_check_completed_at      = previous_dns_check_completed_at
            @mailer_config.provider_check_completed_at = previous_provider_check_completed_at
            @mailer_config.updated                     = Familia.now.to_i
            @mailer_config.save_fields(:verification_status, :dns_check_completed_at, :provider_check_completed_at, :updated)
            raise
          ensure
            lock&.release(lock_token) if lock_token
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
