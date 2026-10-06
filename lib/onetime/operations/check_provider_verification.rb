# lib/onetime/operations/check_provider_verification.rb
#
# frozen_string_literal: true

require_relative '../mail/mailer'
require_relative '../mail/provider_registry'
require_relative '../jobs/workers/job_lifecycle'

module Onetime
  module Operations
    # Ask the sending provider whether a custom sender domain is verified and
    # close the MailerConfig's provider check with the answer.
    #
    # Extracted from DomainValidationWorker so the jobs-disabled fallback in
    # Jobs::Publisher#enqueue_domain_validation runs the SAME check. That
    # fallback used to mark the provider check completed with
    # provider_verified left unknown, so computed_verification_status settled
    # on 'failed' while verification_status — written from DNS alone — said
    # 'verified'. One code path, one answer.
    #
    # ## provider_verified is tri-state
    #
    # Two situations look alike but must not behave alike, so they are told
    # apart by whether the check RAN, not by the verified value alone:
    #
    # - The check never ran (non-provisioning provider such as smtp, or the
    #   provider's required credentials are missing): fall back to the DNS
    #   result. Degraded mode, better than leaving nil.
    # - The check ran but was inconclusive (verified: nil — rotated API key,
    #   provider API error, transport failure): leave provider_verified
    #   UNTOUCHED and keep it out of save_fields. An error must never demote;
    #   a blip would otherwise flip a verified domain to failed on the next
    #   scheduled check. Only an authoritative provider "no" may demote.
    #
    # Any raise inside the check completes the job without touching
    # provider_verified, so the caller's own flow carries on.
    class CheckProviderVerification
      # @param mailer_config [Onetime::CustomDomain::MailerConfig]
      # @param dns_all_verified [Boolean] ValidateSenderDomain's all_verified,
      #   the degraded-mode fallback when the provider check never runs
      # @param domain_id [String] for log lines
      # @param logger [#info, #error]
      def initialize(mailer_config:, dns_all_verified:, domain_id:, logger: Onetime.get_logger('Operations'))
        @mailer_config    = mailer_config
        @dns_all_verified = dns_all_verified
        @domain_id        = domain_id
        @logger           = logger
      end

      # @return [void]
      def call
        lifecycle             = Onetime::Jobs::Workers::JobLifecycle
        provider_result       = nil
        provider_api_verified = nil

        provider = @mailer_config.effective_provider
        if Onetime::Mail::ProviderRegistry.provisioning_provider?(provider)
          require_relative '../mail/sender_strategies'
          sender_strategy = Onetime::Mail::SenderStrategies.for_provider(provider)
          creds           = Onetime::Mail::Mailer.provider_credentials(provider)

          # Guard on REQUIRED keys, not hash emptiness: key-level checks stay
          # correct even when a builder bakes non-secret defaults into the
          # hash. Skipping here keeps the doomed API call from running (the
          # strategy would return verified: nil anyway under the tri-state
          # contract) and logs exactly which keys are missing.
          missing = Onetime::Mail::ProviderRegistry.missing_required_credentials(provider, creds)
          if missing.empty?
            provider_result       = sender_strategy.check_provider_verification_status(@mailer_config, credentials: creds)
            provider_api_verified = provider_result[:verified]
            @logger.info "Provider verification check: #{@domain_id}",
              provider: provider,
              verified: provider_result[:verified],
              status: provider_result[:status]
          else
            @logger.info "Skipping provider check: missing #{provider} credentials",
              provider: provider,
              missing_keys: missing
          end
        end

        # Persist the provider's current domain status into provider_dns_data
        # so the UI can surface it (e.g. 'verified', 'pending_verification').
        #
        # provider_dns_data is a jsonkey (its own Redis key), so this writes
        # immediately. It must happen BEFORE the scalar assignments below:
        # Familia 2.12 warns when a related key is written while the parent
        # holds unsaved scalar fields. Same ordering as DnsRecordCheckWorker.
        if provider_result
          current_provider_data                  = @mailer_config.provider_dns_data.value || {}
          provider_records                       = provider_result.dig(:details, :dns_records) || []
          @mailer_config.provider_dns_data.value = current_provider_data.merge(
            'status' => provider_result[:status],
            'dns_records' => provider_records,
            'raw_provider_response' => provider_result[:details],
          )
        end

        provider_check_inconclusive = provider_result && provider_api_verified.nil?
        if provider_result.nil?
          @mailer_config.provider_verified = @dns_all_verified
        elsif !provider_check_inconclusive
          @mailer_config.provider_verified = provider_api_verified
        end

        # Record provider status when verification fails (or was inconclusive)
        # so the UI can explain why; cleared on verified: true.
        @mailer_config.last_error = if provider_check_inconclusive
                                      "Provider check inconclusive: #{provider_result[:message]}"
                                    elsif provider_api_verified == false && provider_result
                                      "Provider status: #{provider_result[:status]}"
                                    end

        @mailer_config.provider_check_status       = lifecycle::COMPLETED
        @mailer_config.provider_check_completed_at = Familia.now.to_i
        @mailer_config.updated                     = Familia.now.to_i
        save_list                                  = [:provider_check_status, :provider_check_completed_at, :last_error, :updated]
        save_list.unshift(:provider_verified) unless provider_check_inconclusive
        @mailer_config.save_fields(*save_list)
      rescue StandardError => ex
        # The check failing must not fail the caller. Complete the job (the
        # caller itself did not crash) without setting provider_verified,
        # since it could not be determined.
        @logger.error "Provider verification check failed for #{@domain_id}", ex
        @mailer_config.provider_check_status       = lifecycle::COMPLETED
        @mailer_config.provider_check_completed_at = Familia.now.to_i
        @mailer_config.updated                     = Familia.now.to_i
        @mailer_config.save_fields(:provider_check_status, :provider_check_completed_at, :updated)
      end
    end
  end
end
