# apps/api/domains/logic/sender_config/validate_sender_config.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/mailer_config'
require 'onetime/jobs/publisher'
require 'onetime/jobs/workers/job_lifecycle'
require_relative 'base'
require_relative 'serializers'
require_relative 'change_logger'

module DomainsAPI
  module Logic
    module SenderConfig
      # POST Domain Sender DNS Validation (async)
      #
      # Triggers DNS record verification for a custom domain's mail sender
      # configuration. Sets verification_status to 'pending' and enqueues
      # background jobs for actual DNS lookups.
      #
      # The caller can poll GET /:extid/email-config to observe the status
      # transition from 'pending' to 'verified' or 'failed'.
      #
      # Requires the requesting user to be an organization owner with
      # custom_mail_sender entitlement.
      #
      # ## Enqueued Workers
      #
      # This endpoint enqueues TWO workers that update different fields:
      #
      # 1. DnsRecordCheckWorker (fact-finding, fast):
      #    - Populates: dns_check_results.value (Array with dns_exists, value_matches)
      #    - Populates: dns_check_completed_at (timestamp)
      #    - Does NOT set verification_status
      #
      # 2. DomainValidationWorker (verification, may call provider API):
      #    - Populates: verification_status ('verified' | 'failed')
      #    - Populates: provider_check_completed_at (timestamp)
      #    - Uses DomainValidation::SenderStrategies (different from #1)
      #
      # ## Expected State After Completion
      #
      # Poll for: both dns_check_completed_at AND provider_check_completed_at
      # present. Then read verification_status for the final determination.
      #
      # The dns_check_results provide diagnostic detail (which records exist,
      # which values match), while verification_status is the boolean outcome.
      #
      class ValidateSenderConfig < Base
        include Serializers
        include ChangeLogger

        attr_reader :mailer_config

        # What a revalidation resets, and its rollback restores.
        VERIFICATION_RESET_FIELDS = %i[
          verification_status dns_check_status provider_check_status dns_verified
          provider_verified dns_check_completed_at provider_check_completed_at
        ].freeze

        def process_params
          @domain_id = sanitize_identifier(params['extid'])
        end

        def raise_concerns
          raise_form_error('Authentication required', field: :user_id, error_type: :authentication_required) if cust.anonymous?
          raise_form_error('Domain ID required', field: :domain_id, error_type: :missing) if @domain_id.to_s.empty?

          authorize_sender_config!(@domain_id)

          @mailer_config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@custom_domain.identifier)
          raise_form_error('No sender configuration found for this domain', field: :domain_id, error_type: :missing) unless @mailer_config

          # Require from_address before validation makes sense
          # (provider is resolved from installation-level configuration)
          if @mailer_config.from_address.to_s.empty?
            raise_form_error('Sender configuration must have from_address before validation', field: :from_address, error_type: :missing)
          end

          # Require provisioned DNS records: without them there is nothing to
          # check, and enqueueing would clear verification state for nothing.
          unless @mailer_config.provisioned?
            raise_form_error('Sender configuration must be provisioned before validation', field: :domain_id, error_type: :invalid)
          end
        end

        def process
          OT.ld "[ValidateSenderConfig] Triggering async DNS validation for domain #{@domain_id} by user #{cust.extid}"

          # Acquire lock to prevent concurrent revalidation requests
          lock       = Familia::Lock.new("domain:#{@custom_domain.identifier}:revalidate")
          lock_token = lock.acquire(ttl: 60)
          raise_form_error('Validation already in progress. Please try again.', field: :domain_id, error_type: :conflict) unless lock_token

          model    = Onetime::CustomDomain::MailerConfig
          previous = nil

          begin
            lifecycle = Onetime::Jobs::Workers::JobLifecycle

            # Reset the record as stored now (GuardedConfigWrites), keeping
            # the values it replaces for the rollback. A stale copy would
            # write back, and later restore, whatever a job recorded since
            # raise_concerns loaded it.
            #
            # Set job lifecycle status to QUEUED (jobs are about to be enqueued)
            # Clear outcome fields (nil = unknown/pending)
            # Clear completion timestamps so the UI reflects immediately
            @mailer_config, previous = guarded_config_write do
              model.update_for_domain!(@custom_domain.identifier) do |stored|
                replaced = VERIFICATION_RESET_FIELDS.to_h { |name| [name, stored.public_send(name)] }

                stored.verification_status         = VERIFICATION_STATUS_PENDING
                stored.dns_check_status            = lifecycle::QUEUED
                stored.provider_check_status       = lifecycle::QUEUED
                stored.dns_verified                = nil
                stored.provider_verified           = nil
                stored.dns_check_completed_at      = ''
                stored.provider_check_completed_at = ''
                stored.updated                     = Familia.now.to_i
                replaced
              end
            end

            # Also clear dns_check_results so stale booleans (dns_exists,
            # value_matches) don't show as verified during pending state. A
            # jsonkey (its own Redis key) writes on assignment.
            previous_dns_check_results            = @mailer_config.dns_check_results&.value
            @mailer_config.dns_check_results.value = nil

            # Enqueue both background validation jobs
            # (user explicitly requested fresh verification via "Verify Now")
            Onetime::Jobs::Publisher.enqueue_dns_record_check(@custom_domain.identifier)
            Onetime::Jobs::Publisher.enqueue_domain_validation(
              @custom_domain.identifier,
              bypass_cache: true,
            )
          rescue StandardError
            # Rollback: restore previous status, lifecycle fields, outcomes, timestamps,
            # and dns_check_results so nothing stays stuck in 'pending'. Nothing
            # to restore when the reset itself did not happen.
            if previous
              model.update_for_domain_if(@custom_domain.identifier, ->(_stored) { true }) do |stored|
                previous.each { |name, value| stored.public_send(:"#{name}=", value) }
                stored.updated = Familia.now.to_i
              end
              @mailer_config.dns_check_results.value = previous_dns_check_results
            end
            raise
          ensure
            lock&.release(lock_token) if lock_token
          end

          log_sender_config_event(
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
