# lib/onetime/models/custom_domain/mailer_config.rb
#
# frozen_string_literal: true

#
# CustomDomain::MailerConfig - Per-domain mail sender configuration
#
# This model stores mail sender credentials bound to a specific CustomDomain.
# This enables per-domain email configuration where different domains owned
# by the same organization can use different mail providers and sender
# identities.
#
# Use Cases:
#   - Brand consistency: secrets.acme.eu sends from noreply@acme.eu, secrets.acme.com from noreply@acme.com
#   - Provider isolation: one domain uses SES, another uses SendGrid
#   - Compliance: regional domains use region-specific mail infrastructure
#
# Credential Binding:
#   The api_key is encrypted with AAD (Additional Authenticated Data) bound
#   to domain_id, preventing credential swapping attacks between domains.
#
# Verification Semantics:
#   - Changing from_address resets verified_at (DNS verification no longer applies)
#   - Changing api_key, from_name, or reply_to does NOT reset verified_at
#
# DNS Data Storage (two-field design):
#   - provider_dns_data (jsonkey): Raw provider response hash, shape varies by provider.
#     Preserved for re-normalization and provider-specific operations.
#   - dns_records (jsonkey): Normalized Array of record hashes for UI display,
#     each with :type, :name, :value keys. Populated during provisioning.
#
module Onetime
  class CustomDomain < Familia::Horreum
    class MailerConfig < Familia::Horreum
      include Familia::Features::Autoloader

      # Supported mail provider types.
      # See lib/onetime/mail/mailer.rb for provider implementations.
      PROVIDER_TYPES = %w[smtp ses sendgrid lettermint].freeze

      prefix :custom_domain__mailer_config

      feature :encrypted_fields

      # domain_id is the CustomDomain's identifier (objid), used as our key.
      # This creates a 1:1 relationship: one mailer config per domain.
      identifier_field :domain_id
      field :domain_id

      # Provider selection
      field :provider         # One of PROVIDER_TYPES

      # Sender identity fields
      field :from_name        # Display name for sender
      field :from_address     # Sender email address
      field :reply_to         # Reply-to address

      # DNS verification state (stored, updated by workers when both jobs complete)
      # Values: 'pending' | 'verified' | 'failed'
      # Updated by: DomainValidationWorker (after both jobs finish)
      field :verification_status
      field :verified_at          # Timestamp, cleared when from_address changes

      # Job lifecycle status fields (track WHERE the job is, not the outcome)
      # Values: queued, processing, completed, failed
      # See: lib/onetime/jobs/workers/job_lifecycle.rb
      field :dns_check_status       # DnsRecordCheckWorker lifecycle
      field :provider_check_status  # DomainValidationWorker lifecycle

      # Verification outcome fields (track WHAT the result was)
      # nil = pending/unknown, true = passed, false = failed
      # These are set by workers after check completes
      field :dns_verified           # All DNS records have value_matches=true
      field :provider_verified      # Provider API confirms domain is verified

      # Sending mode: 'platform' (OTS manages DNS via provider API) or
      # future modes like 'byodns' (customer manages DNS manually).
      # Currently only 'platform' is supported.
      field :sending_mode

      # Provider-specific DNS/identity data returned from provider APIs.
      # Shape varies by provider:
      #   SES: { dkim_tokens: [...], region: "us-east-1", identity_arn: "..." }
      #   SendGrid: { subdomain: "em1234", dns_records: [...] }
      jsonkey :provider_dns_data

      # Normalized DNS records for UI display.
      # Uniform array format: [{ type: 'CNAME', name: '...', value: '...' }, ...]
      # Populated during provisioning from provider-specific dns_records.
      jsonkey :dns_records

      # Encrypted credential storage with domain-bound AAD
      encrypted_field :api_key, aad_fields: [:domain_id]

      # Distributed lock for concurrent provisioning protection
      lock :provisioning

      # General state
      field :enabled          # Boolean string ('true'/'false')

      # Per-record DNS check results from DnsRecordCheckWorker.
      # Array of hashes: [{type:, name:, value:, dns_exists:, value_matches:, error:}, ...]
      # Pure fact-finding data — no pass/fail judgement.
      jsonkey :dns_check_results

      # Timestamps for dual verification completion tracking.
      # Cleared when re-validate is triggered; set by respective workers.
      field :dns_check_completed_at       # Unix timestamp, set by DnsRecordCheckWorker
      field :provider_check_completed_at  # Unix timestamp, set by DomainValidationWorker

      # Verification tracking fields (for caching and metrics)
      field :last_check_at      # Unix timestamp of last verification attempt
      field :check_duration_ms  # Duration of last check in milliseconds
      field :check_count        # Total number of verification attempts
      field :last_error         # Last error message if verification failed

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      def init
        self.enabled             ||= 'false'
        self.verification_status ||= 'pending'
        self.sending_mode        ||= 'platform'
        # Job lifecycle fields default to nil (no job enqueued yet)
        # Outcome fields default to nil (unknown/pending)
      end

      # Check if this mailer config is enabled.
      #
      # @return [Boolean] true if mailer config is active
      def enabled?
        enabled.to_s == 'true'
      end

      # Check if the sender address has been verified via DNS.
      #
      # @return [Boolean] true if verification_status is 'verified'
      def verified?
        verification_status == 'verified'
      end

      # Compute the effective verification status from outcome fields.
      #
      # This provides backward compatibility: code that reads verification_status
      # will get a value derived from the more granular outcome fields.
      #
      # Logic:
      #   - If either job is still active (queued/processing): 'pending'
      #   - If both outcomes are true: 'verified'
      #   - If either outcome is false: 'failed'
      #   - If outcomes are nil but jobs completed: 'failed' (no data = failure)
      #   - Default: 'pending'
      #
      # @return [String] 'pending', 'verified', or 'failed'
      def computed_verification_status
        require_relative '../../jobs/workers/job_lifecycle'
        lifecycle = Onetime::Jobs::Workers::JobLifecycle

        # If either job is still in progress, we're pending
        return 'pending' if lifecycle.active?(dns_check_status)
        return 'pending' if lifecycle.active?(provider_check_status)

        # If we have outcome data, use it
        dns_ok      = parse_boolean_field(dns_verified)
        provider_ok = parse_boolean_field(provider_verified)

        # Both must pass for verified status
        if dns_ok == true && provider_ok == true
          'verified'
        elsif dns_ok == false || provider_ok == false ||
              (lifecycle.terminal?(dns_check_status) && lifecycle.terminal?(provider_check_status))
          'failed'
        else
          'pending'
        end
      end

      # Check if both verification jobs have completed (regardless of outcome).
      #
      # @return [Boolean] true if both dns_check_status and provider_check_status are terminal
      def jobs_completed?
        require_relative '../../jobs/workers/job_lifecycle'
        lifecycle = Onetime::Jobs::Workers::JobLifecycle

        lifecycle.terminal?(dns_check_status) && lifecycle.terminal?(provider_check_status)
      end

      # Check if any verification job is still in progress.
      #
      # @return [Boolean] true if either job is queued or processing
      def jobs_in_progress?
        require_relative '../../jobs/workers/job_lifecycle'
        lifecycle = Onetime::Jobs::Workers::JobLifecycle

        lifecycle.active?(dns_check_status) || lifecycle.active?(provider_check_status)
      end

      # Update verification_status from outcome fields and persist.
      #
      # Called by workers after both jobs complete. Derives the final status
      # from dns_verified and provider_verified, then stores it.
      #
      # @return [String] the new verification_status value
      def update_verification_status!
        new_status               = computed_verification_status
        self.verification_status = new_status
        self.updated             = Familia.now.to_i
        save_fields(:verification_status, :updated)
        new_status
      end

      private

      # Parse a boolean field that may be stored as string, boolean, or nil.
      #
      # @param value [String, Boolean, nil] The field value
      # @return [Boolean, nil] true, false, or nil if unknown
      def parse_boolean_field(value)
        case value
        when true, 'true'
          true
        when false, 'false'
          false
        end
      end

      public

      # Update the from_address, resetting verification state.
      #
      # Changing the sender address invalidates any prior DNS verification
      # (DKIM/SPF records are bound to the sender domain), so verified_at
      # is cleared and verification_status reverts to 'pending'.
      #
      # @param new_address [String] The new sender email address
      # @return [void]
      def update_from_address(new_address)
        self.from_address        = new_address
        self.verified_at         = nil
        self.verification_status = 'pending'
        self.updated             = Familia.now.to_i
        save
      end

      # Rotate the API key without affecting verification state.
      #
      # Credential rotation is independent of DNS verification -- the
      # DKIM/SPF records don't change when the API key changes.
      #
      # @param new_api_key [String] The new provider API key
      # @return [void]
      def rotate_credentials(new_api_key)
        self.api_key = new_api_key
        self.updated = Familia.now.to_i
        save
      end

      # Load the associated CustomDomain record.
      #
      # @return [CustomDomain, nil] The domain or nil if not found
      def custom_domain
        Onetime::CustomDomain.find_by_identifier(domain_id)
      rescue Onetime::RecordNotFound
        nil
      end

      # Load the owning Organization via the CustomDomain.
      #
      # @return [Organization, nil] The organization or nil if not found
      def organization
        custom_domain&.primary_organization
      end

      # Validate that all required fields are present.
      #
      # @return [Array<String>] List of validation error messages
      def validation_errors
        errors = []

        errors << 'domain_id is required' if domain_id.to_s.empty?
        # Provider is optional - when empty, resolved from installation config
        if !provider.to_s.empty? && !PROVIDER_TYPES.include?(provider)
          errors << "provider must be one of: #{PROVIDER_TYPES.join(', ')}"
        end
        errors << 'from_address is required' if from_address.to_s.empty?

        errors
      end

      # Check if the configuration is valid.
      #
      # @return [Boolean] true if no validation errors
      def valid?
        validation_errors.empty?
      end

      # Record a verification check attempt with timing and optional error.
      #
      # Updates tracking fields for caching decisions and operational metrics.
      # Called by ValidateSenderDomain after each verification attempt.
      #
      # Uses save_fields for field-specific persistence to avoid race
      # conditions where a full save could overwrite concurrent updates
      # to other fields.
      #
      # @param duration_ms [Integer] How long the check took in milliseconds
      # @param error [String, nil] Error message if the check failed
      # @return [void]
      def record_check_attempt(duration_ms, error = nil)
        self.last_check_at     = Familia.now.to_i
        self.check_duration_ms = duration_ms.to_i
        self.check_count       = (check_count.to_i + 1).to_s
        self.last_error        = error
        self.updated           = Familia.now.to_i
        save_fields(:last_check_at, :check_duration_ms, :check_count, :last_error, :updated)
      end

      # Check if a recent verification check was performed.
      #
      # Used for caching decisions to avoid excessive DNS lookups.
      #
      # @param max_age_seconds [Integer] Maximum age for a check to be considered recent
      # @return [Boolean] true if a check was performed within max_age_seconds
      def check_recent?(max_age_seconds = 300)
        return false if last_check_at.to_s.empty?

        (Familia.now.to_i - last_check_at.to_i) < max_age_seconds
      end

      # Check if the sender domain has been provisioned.
      #
      # A domain is considered provisioned when dns_records contains
      # normalized records from the provider API (SES, SendGrid, etc.).
      #
      # @return [Boolean] true if dns_records is populated
      def provisioned?
        data = dns_records&.value
        data.is_a?(Array) && !data.empty?
      end

      # Build DNS records required for email authentication.
      #
      # Returns the DNS records that must be configured at the domain registrar.
      # After provisioning, this returns the actual records from the provider,
      # enriched with per-record DNS check results when available.
      #
      # Each record includes:
      #   - type: DNS record type (CNAME, TXT, etc.)
      #   - name: DNS hostname
      #   - value: DNS record value
      #   - status: Overall verification status ('pending', 'verified', 'failed')
      #   - dns_exists: Whether the DNS record was found (from DnsRecordCheckWorker)
      #   - value_matches: Whether the DNS value matches provisioned value
      #
      # @return [Array<Hash>] DNS records for user to configure
      def required_dns_records
        return [] unless provisioned?

        data                   = dns_records.value
        dns_checks             = dns_check_results&.value || []
        provider_data          = provider_dns_data&.value || {}
        provider_records       = provider_data['dns_records'] || []
        domain_provider_status = provider_data['status']
        current_status         = verification_status || 'pending'

        data.map do |record|
          name  = record['name']
          check = dns_checks.find { |c| c['name'] == name }

          # Per-record status from DNS check facts when available;
          # fall back to overall status only when no check data exists yet.
          per_record_status = if check
                                check['value_matches'] ? 'verified' : 'failed'
                              else
                                current_status
                              end

          result = {
            'type' => record['type'],
            'name' => name,
            'value' => record['value'],
            'status' => per_record_status,
          }
          if check
            result['dns_exists']    = check['dns_exists']
            result['value_matches'] = check['value_matches']
          end

          apply_provider_verification(result, name, provider_records, domain_provider_status)

          result.compact
        end
      end

      # Set provider_verified on a record hash by matching against provider
      # DNS records, falling back to domain-level status.
      #
      # Lettermint uses 'active' for verified DNS records and 'verified'
      # at the domain level. provider_status_verified? accepts both.
      #
      # @param result [Hash] Record hash to annotate (mutated in place)
      # @param name [String] DNS record hostname to match
      # @param provider_records [Array<Hash>] Per-record provider data
      # @param domain_provider_status [String, nil] Domain-level provider status
      def apply_provider_verification(result, name, provider_records, domain_provider_status)
        if provider_records.any?
          provider_rec                = provider_records.find { |p| p['name'].to_s == name }
          record_status               = provider_rec&.dig('status')
          effective_status            = record_status || domain_provider_status
          result['provider_verified'] = provider_status_verified?(effective_status) unless effective_status.nil?
        elsif domain_provider_status
          result['provider_verified'] = provider_status_verified?(domain_provider_status)
        end
      end

      # Whether a provider status string indicates verified.
      #
      # Lettermint uses 'active' for verified DNS records and 'verified'
      # at the domain level. Other providers may use 'verified' directly.
      #
      # @param status [String] Provider status value
      # @return [Boolean]
      def provider_status_verified?(status)
        %w[verified active].include?(status.to_s.downcase)
      end

      # Check if both DNS and provider verification have completed.
      #
      # Used by the frontend to determine when polling can stop.
      #
      # @return [Boolean] true if both checks have run since last re-validate
      def both_checks_complete?
        !dns_check_completed_at.to_s.empty? && !provider_check_completed_at.to_s.empty?
      end

      # Resolve effective provider for this mailer config.
      #
      # Uses the config's provider field if set, otherwise falls back to
      # installation-level provider from Mailer.determine_provider.
      #
      # @return [String, nil] Provider name or nil if not resolvable
      def effective_provider
        resolved = provider.to_s.strip
        return resolved unless resolved.empty?

        # Fallback to installation config
        Onetime::Mail::Mailer.send(:determine_provider)
      end

      class << self
        # Find mailer config by domain ID.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [CustomDomain::MailerConfig, nil] The config or nil if not found
        def find_by_domain_id(domain_id)
          return nil if domain_id.to_s.empty?

          load(domain_id)
        rescue Onetime::RecordNotFound
          nil
        end

        # Load sender config with graceful fallback.
        #
        # Wraps find_by_domain_id with broader error handling. Returns nil
        # on missing config or any error — callers treat nil as "use
        # system default sender config".
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [CustomDomain::MailerConfig, nil] The config or nil
        def load_for_domain(domain_id)
          config = find_by_domain_id(domain_id)
          unless config
            OT.info "[MailerConfig] No sender config for domain_id=#{domain_id}, using global mailer"
            return nil
          end
          config
        rescue StandardError => ex
          OT.le "[MailerConfig] Failed to load sender config for domain_id=#{domain_id}: #{ex.message}"
          nil
        end

        # Check if a domain has mailer configuration.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if mailer config exists
        def exists_for_domain?(domain_id)
          return false if domain_id.to_s.empty?

          exists?(domain_id)
        end

        # Create a new mailer config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param attrs [Hash] Configuration attributes
        # @return [CustomDomain::MailerConfig] The created config
        # @raise [Onetime::Problem] if config already exists or validation fails
        def create!(domain_id:, **attrs)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?
          raise Onetime::Problem, 'Mailer config already exists for this domain' if exists_for_domain?(domain_id)

          config = new(domain_id: domain_id)

          # Set provider and sender identity fields
          config.provider     = attrs[:provider] if attrs.key?(:provider)
          config.from_name    = attrs[:from_name] if attrs.key?(:from_name)
          config.from_address = attrs[:from_address] if attrs.key?(:from_address)
          config.reply_to     = attrs[:reply_to] if attrs.key?(:reply_to)
          config.enabled      = attrs[:enabled].to_s if attrs.key?(:enabled)

          # Set verification and mode fields
          config.verification_status = attrs[:verification_status] if attrs.key?(:verification_status)
          config.sending_mode        = attrs[:sending_mode] if attrs.key?(:sending_mode)

          # Initialize timestamps
          now            = Familia.now.to_i
          config.created = now
          config.updated = now

          unless config.valid?
            raise Onetime::Problem, config.validation_errors.join('; ')
          end

          config.save

          # Set encrypted fields AFTER save so the AAD context includes
          # aad_fields values (Familia's build_aad uses record.exists? to
          # decide whether to include aad_fields in the AAD hash). Setting
          # api_key before save would encrypt with pre-save AAD, but reveal
          # after save computes post-save AAD -- causing decryption failure.
          if attrs.key?(:api_key)
            config.api_key = attrs[:api_key]
            config.commit_fields
          end

          config
        end

        # Delete mailer config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if deleted, false if not found
        def delete_for_domain!(domain_id)
          return false if domain_id.to_s.empty?

          config = find_by_domain_id(domain_id)
          return false unless config

          config.destroy!

          true
        end

        # List all domain mailer configs.
        #
        # @return [Array<CustomDomain::MailerConfig>] All configs (newest first)
        def all
          instances.revrangeraw(0, -1).filter_map do |identifier|
            load(identifier)
          rescue Onetime::RecordNotFound
            nil
          end
        end

        # Count of domains with mailer configuration.
        #
        # @return [Integer] Number of mailer configs
        def count
          instances.size
        end
      end
    end
  end
end
