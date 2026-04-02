# lib/onetime/operations/validate_sender_domain.rb
#
# frozen_string_literal: true

require_relative '../domain_validation/sender_strategies/strategy'
require_relative '../security/dns_rate_limiter'

module Onetime
  module Operations
    #
    # Validates DNS records for a custom domain's mail sender configuration.
    # Delegates DNS verification to provider-specific sender strategies.
    #
    # This operation orchestrates the verification flow:
    #   1. Loads the associated CustomDomain from the MailerConfig
    #   2. Selects the appropriate sender strategy (or uses provided override)
    #   3. Delegates DNS record verification to the strategy
    #   4. Optionally persists verification state back to the model
    #
    # Single domain usage:
    #   result = ValidateSenderDomain.new(mailer_config: config).call
    #   result.all_verified        # => true/false
    #   result.verification_status # => "verified" or "failed"
    #
    # Without persistence (dry-run / preview):
    #   result = ValidateSenderDomain.new(mailer_config: config, persist: false).call
    #
    # Query required DNS records (no verification):
    #   records = ValidateSenderDomain.required_records(mailer_config: config)
    #   # => [{type:, host:, value:, purpose:}, ...]
    #
    class ValidateSenderDomain
      include Onetime::LoggerMethods
      include Onetime::Security::DnsRateLimiter

      # Immutable result for sender domain validation
      Result = Data.define(
        :domain,              # String - the domain name
        :provider,            # String - provider type
        :dns_records,         # Array of record verification hashes
        :all_verified,        # Boolean - all records pass?
        :verification_status, # String - "verified" or "failed" or "pending"
        :verified_at,         # Time or nil
        :persisted,           # Boolean - was the model updated?
        :error,               # String or nil
        :rate_limit,          # Hash - rate limit status (remaining, reset_in, etc.)
      ) do
        def success?
          error.nil?
        end

        def to_h
          {
            domain: domain,
            provider: provider,
            dns_records: dns_records,
            all_verified: all_verified,
            verification_status: verification_status,
            verified_at: verified_at&.iso8601,
            persisted: persisted,
            error: error,
            rate_limit: rate_limit,
          }.compact
        end
      end

      # @param mailer_config [Onetime::CustomDomain::MailerConfig] The sender config to validate
      # @param strategy [Object, nil] Optional strategy override; auto-selected from provider if nil
      # @param options [Hash] Provider-specific options forwarded to the strategy
      #   constructor (e.g. region: for SES, subdomain: for SendGrid)
      # @param persist [Boolean] Whether to update the model with verification results
      # @param bypass_cache [Boolean] When true, skips DNS cache and queries fresh records
      def initialize(mailer_config:, strategy: nil, options: {}, persist: true, bypass_cache: false)
        @mailer_config = mailer_config
        @strategy      = strategy
        @options       = options
        @persist       = persist
        @bypass_cache  = bypass_cache
      end

      # Executes sender domain DNS validation.
      #
      # Validation-related failures are captured in the Result, but this method
      # may still raise exceptions (e.g. ArgumentError or unexpected rate-limit
      # errors) when configuration or environment is invalid.
      # Rate limits are enforced: max 10 verifications per domain per hour.
      #
      # @return [Result] Verification result
      def call
        domain_name   = nil
        rate_limit    = nil
        custom_domain = load_custom_domain
        domain_name   = custom_domain&.display_domain || extract_domain_from_address

        # Check rate limit before performing DNS verification.
        # This prevents excessive DNS queries and potential abuse.
        rate_limit = check_dns_rate_limit!(@mailer_config.domain_id)

        logger.info 'Validating sender domain',
          domain: domain_name,
          provider: effective_provider,
          persist: @persist,
          bypass_cache: @bypass_cache,
          rate_limit_remaining: rate_limit[:remaining]

        # Verify DNS records via the provider strategy (with timing for observability)
        start_time   = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        dns_records  = strategy.verify_dns_records(@mailer_config, bypass_cache: @bypass_cache)
        duration_ms  = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
        all_verified = dns_records.all? { |record| record[:verified] }

        verification_status = all_verified ? 'verified' : 'failed'
        verified_at         = all_verified ? Time.now : nil

        # Persist state changes when enabled
        persisted = false
        if @persist
          persisted = persist_verification(verification_status, verified_at)
          @mailer_config.record_check_attempt(duration_ms, nil)
        end

        logger.info 'Sender domain validation complete',
          domain: domain_name,
          provider: effective_provider,
          status: verification_status,
          records_checked: dns_records.size,
          duration_ms: duration_ms,
          persisted: persisted

        Result.new(
          domain: domain_name,
          provider: effective_provider.to_s,
          dns_records: dns_records,
          all_verified: all_verified,
          verification_status: verification_status,
          verified_at: verified_at,
          persisted: persisted,
          error: nil,
          rate_limit: rate_limit,
        )
      rescue ArgumentError
        raise # programming/config error — don't mask as validation failure
      rescue Onetime::LimitExceeded => ex
        # Rate limit exceeded - return error result with rate limit info
        logger.warn 'DNS verification rate limited',
          domain: domain_name,
          domain_id: @mailer_config&.domain_id,
          retry_after: ex.retry_after

        # Record the rate-limited attempt for metrics (duration is 0 since no DNS lookup occurred)
        @mailer_config.record_check_attempt(0, "Rate limited: retry after #{ex.retry_after}s") if @persist && @mailer_config

        Result.new(
          domain: domain_name,
          provider: effective_provider.to_s,
          dns_records: [],
          all_verified: false,
          verification_status: 'rate_limited',
          verified_at: nil,
          persisted: false,
          error: ex.message,
          rate_limit: {
            remaining: 0,
            reset_in: ex.retry_after,
            current: ex.attempts,
            limit: ex.max_attempts,
          },
        )
      rescue StandardError => ex
        # Calculate duration if timing was started (exception may occur before DNS call)
        error_duration_ms = start_time ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round : nil

        logger.error 'Sender domain validation failed',
          domain: domain_name,
          provider: effective_provider,
          status: 'failed',
          error: ex.message,
          error_class: ex.class.name,
          duration_ms: error_duration_ms

        # Record the failed attempt for observability
        @mailer_config.record_check_attempt(error_duration_ms, ex.message) if @persist && @mailer_config

        Result.new(
          domain: domain_name,
          provider: effective_provider.to_s,
          dns_records: [],
          all_verified: false,
          verification_status: 'failed',
          verified_at: nil,
          persisted: false,
          error: ex.message,
          rate_limit: rate_limit,
        )
      end

      # Returns the DNS records required for sender verification without
      # performing any verification checks. Useful for displaying setup
      # instructions to the user.
      #
      # @param mailer_config [Onetime::CustomDomain::MailerConfig] The sender config
      # @param strategy [Object, nil] Optional strategy override
      # @param options [Hash] Provider-specific options (e.g. region: for SES)
      # @return [Array<Hash>] Required DNS records [{type:, host:, value:, purpose:}, ...]
      def self.required_records(mailer_config:, strategy: nil, options: {})
        provider          = resolve_effective_provider(mailer_config)
        resolved_strategy = strategy || resolve_strategy(provider, options)
        resolved_strategy.required_dns_records(mailer_config)
      end

      # Resolve effective provider for a mailer config.
      #
      # Uses mailer_config.provider if set, otherwise falls back to
      # installation-level provider from Mailer.determine_provider.
      #
      # @param mailer_config [Onetime::CustomDomain::MailerConfig] The mailer config
      # @return [String, nil] Provider name or nil if not resolvable
      private_class_method def self.resolve_effective_provider(mailer_config)
        provider = mailer_config.provider.to_s.strip
        return provider unless provider.empty?

        # Fallback to installation config
        Onetime::Mail::Mailer.send(:determine_provider)
      end

      private

      # Resolve the sender strategy, using the override if provided or
      # auto-selecting based on the mailer config's provider type.
      #
      # @return [Object] A strategy responding to #verify_dns_records and #required_dns_records
      def strategy
        @strategy ||= self.class.send(:resolve_strategy, effective_provider, @options)
      end

      # Resolve effective provider for this operation.
      #
      # Uses mailer_config.provider if set, otherwise falls back to
      # installation-level provider from Mailer.determine_provider.
      #
      # @return [String, nil] Provider name or nil if not resolvable
      def effective_provider
        provider = @mailer_config.provider.to_s.strip
        return provider unless provider.empty?

        # Fallback to installation config
        Onetime::Mail::Mailer.send(:determine_provider)
      end

      # Factory lookup for sender strategies by provider name.
      #
      # @param provider [String] Provider type (e.g. "smtp", "ses", "sendgrid")
      # @param options [Hash] Provider-specific options forwarded to the strategy
      # @return [Object] Strategy instance
      private_class_method def self.resolve_strategy(provider, options = {})
        Onetime::DomainValidation::SenderStrategies::SenderStrategy.for_provider(provider, options)
      end

      # Load the CustomDomain associated with this mailer config.
      #
      # @return [Onetime::CustomDomain, nil] The domain or nil if not found
      def load_custom_domain
        return nil if @mailer_config.domain_id.to_s.empty?

        Onetime::CustomDomain.find_by_identifier(@mailer_config.domain_id)
      rescue Onetime::RecordNotFound
        logger.warn 'CustomDomain not found for mailer config',
          domain_id: @mailer_config.domain_id
        nil
      end

      # Extract the domain portion from the from_address as a fallback
      # when the CustomDomain record cannot be loaded.
      #
      # @return [String, nil] Domain from email address or nil
      def extract_domain_from_address
        address = @mailer_config.from_address.to_s
        return nil unless address.include?('@')

        address.split('@').last
      end

      # Persist verification state to the mailer config model.
      #
      # @param verification_status [String] "verified" or "failed"
      # @param verified_at [Time, nil] Verification timestamp
      # @return [Boolean] Whether changes were saved
      def persist_verification(verification_status, verified_at)
        @mailer_config.verification_status = verification_status
        @mailer_config.verified_at         = verified_at&.to_i&.to_s
        @mailer_config.updated             = Familia.now.to_i
        # Partial save: only write verification fields, not the full record.
        # A full save would overwrite api_key with stale in-memory ciphertext
        # if a concurrent rotate_credentials call updated it since we loaded.
        @mailer_config.save_fields(:verification_status, :verified_at, :updated)

        true
      rescue StandardError => ex
        logger.error 'Failed to persist sender verification state',
          domain_id: @mailer_config.domain_id,
          error: ex.message
        false
      end

      # @return [SemanticLogger::Logger] Logger instance
      def logger
        @logger ||= Onetime.get_logger('Operations')
      end
    end
  end
end
