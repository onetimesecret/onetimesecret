# lib/onetime/operations/verify_domain.rb
#
# frozen_string_literal: true

module Onetime
  module Operations
    #
    # Verifies domain ownership and SSL status for custom domains.
    # Extracted from API logic for reuse in CLI tools and testing.
    #
    # Single domain usage:
    #   result = VerifyDomain.new(domain: custom_domain).call
    #   result.dns_validated  # => true/false
    #   result.ssl_ready      # => true/false
    #
    # Bulk domain usage:
    #   result = VerifyDomain.new(domains: domain_list, rate_limit: 0.5).call
    #   result.verified_count # => 5
    #   result.results        # => [Result, Result, ...]
    #
    # Options:
    #   - persist: Whether to save changes to Redis (default: true)
    #   - rate_limit: Delay in seconds between API calls in bulk mode (default: 0.5)
    #   - strategy: Custom validation strategy (default: from config)
    #
    class VerifyDomain
      include Onetime::LoggerMethods

      # Immutable result for single domain verification
      Result = Data.define(
        :domain,          # CustomDomain instance
        :previous_state,  # Symbol: :unverified, :pending, :resolving, :verified
        :current_state,   # Symbol: :unverified, :pending, :resolving, :verified
        :dns_validated,   # Boolean: TXT record matches
        :ssl_ready,       # Boolean: has valid SSL certificate
        :is_resolving,    # Boolean: DNS resolving to correct target
        :persisted,       # Boolean: changes were saved
        :error,           # String or nil: error message if failed
      ) do
        def success?
          error.nil?
        end

        def changed?
          previous_state != current_state
        end

        def to_h
          {
            domain: domain&.display_domain,
            previous_state: previous_state,
            current_state: current_state,
            dns_validated: dns_validated,
            ssl_ready: ssl_ready,
            is_resolving: is_resolving,
            persisted: persisted,
            error: error,
          }
        end
      end

      # Immutable result for bulk domain verification
      BulkResult = Data.define(
        :total,           # Integer: total domains processed
        :verified_count,  # Integer: domains with dns_validated=true
        :failed_count,    # Integer: domains with errors
        :skipped_count,   # Integer: domains skipped (already verified, etc.)
        :results,         # Array<Result>: individual results
        :duration_seconds, # Float: total processing time
      ) do
        def success?
          failed_count == 0
        end

        def to_h
          {
            total: total,
            verified_count: verified_count,
            failed_count: failed_count,
            skipped_count: skipped_count,
            duration_seconds: duration_seconds,
            results: results.map(&:to_h),
          }
        end
      end

      # @param domain [Onetime::CustomDomain, nil] Single domain to verify
      # @param domains [Array<Onetime::CustomDomain>, nil] Multiple domains for bulk mode
      # @param strategy [Onetime::DomainValidation::BaseStrategy, nil] Validation strategy
      # @param persist [Boolean] Whether to save changes to Redis
      # @param rate_limit [Float] Delay in seconds between API calls (bulk mode)
      def initialize(domain: nil, domains: nil, strategy: nil, persist: true, rate_limit: 0.5)
        @domain     = domain
        @domains    = domains
        @strategy   = strategy
        @persist    = persist
        @rate_limit = rate_limit

        validate_arguments!
      end

      # Executes domain verification
      #
      # @return [Result, BulkResult] Single or bulk result depending on mode
      def call
        if bulk_mode?
          verify_bulk
        else
          verify_single(@domain)
        end
      end

      private

      def validate_arguments!
        if @domain.nil? && (@domains.nil? || @domains.empty?)
          raise ArgumentError, 'Must provide either domain: or domains:'
        end

        if @domain && @domains&.any?
          raise ArgumentError, 'Cannot provide both domain: and domains:'
        end
      end

      def bulk_mode?
        @domains&.any?
      end

      def strategy
        @strategy ||= Onetime::DomainValidation::Strategy.for_config(OT.conf)
      end

      # Verify a single domain
      #
      # @param domain [Onetime::CustomDomain] Domain to verify
      # @return [Result] Verification result
      def verify_single(domain)
        previous_state = domain.verification_state

        # Perform DNS ownership validation
        dns_result = validate_ownership(domain)

        # Check SSL/resolution status
        status_result = check_status(domain)

        # Persist changes if enabled
        persisted = false
        if @persist && (dns_result[:validated] || status_result[:is_resolving])
          persisted = persist_changes(domain, dns_result, status_result)
        end

        current_state = domain.verification_state

        Result.new(
          domain: domain,
          previous_state: previous_state,
          current_state: current_state,
          dns_validated: dns_result[:validated] || false,
          ssl_ready: status_result[:has_ssl] || false,
          is_resolving: status_result[:is_resolving] || false,
          persisted: persisted,
          error: nil,
        )
      rescue StandardError => ex
        logger.error 'Domain verification failed',
          domain: domain&.display_domain,
          error: ex.message,
          error_class: ex.class.name

        Result.new(
          domain: domain,
          previous_state: domain&.verification_state,
          current_state: domain&.verification_state,
          dns_validated: false,
          ssl_ready: false,
          is_resolving: false,
          persisted: false,
          error: ex.message,
        )
      end

      # Verify multiple domains with rate limiting
      #
      # @return [BulkResult] Aggregated results
      def verify_bulk
        start_time = Time.now
        results    = []

        @domains.each_with_index do |domain, index|
          # Rate limiting between API calls
          sleep(@rate_limit) if index.positive? && @rate_limit.positive?

          result = verify_single(domain)
          results << result
        end

        duration = Time.now - start_time

        BulkResult.new(
          total: results.size,
          verified_count: results.count { |r| r.dns_validated },
          failed_count: results.count { |r| !r.success? },
          skipped_count: 0, # Could be extended for skip logic
          results: results,
          duration_seconds: duration.round(2),
        )
      end

      # Validate domain ownership via TXT record
      #
      # @param domain [Onetime::CustomDomain]
      # @return [Hash] { validated: Boolean, message: String, data: Hash }
      def validate_ownership(domain)
        result = strategy.validate_ownership(domain)
        logger.debug 'DNS validation result',
          domain: domain.display_domain,
          validated: result[:validated]
        result
      rescue StandardError => ex
        logger.error 'DNS validation error',
          domain: domain.display_domain,
          error: ex.message
        { validated: false, message: ex.message, data: nil }
      end

      # Check SSL and resolution status
      #
      # @param domain [Onetime::CustomDomain]
      # @return [Hash] { ready: Boolean, has_ssl: Boolean, is_resolving: Boolean, ... }
      def check_status(domain)
        result = strategy.check_status(domain)

        # Handle vhost not found - try to create it
        if vhost_not_found?(result)
          logger.info 'Vhost not found, attempting to create',
            domain: domain.display_domain
          ensure_vhost_exists(domain)
          result = strategy.check_status(domain)
        end

        logger.debug 'Status check result',
          domain: domain.display_domain,
          ready: result[:ready],
          is_resolving: result[:is_resolving]

        result
      rescue StandardError => ex
        logger.error 'Status check error',
          domain: domain.display_domain,
          error: ex.message
        { ready: false, has_ssl: false, is_resolving: false, message: ex.message }
      end

      # Check if the result indicates vhost was not found (404 from Approximated)
      #
      # @param result [Hash]
      # @return [Boolean]
      def vhost_not_found?(result)
        return false unless result.is_a?(Hash)

        message = result[:message].to_s
        message.include?('Could not find Virtual Host')
      end

      # Ensure the vhost exists in the SSL provider
      #
      # @param domain [Onetime::CustomDomain]
      def ensure_vhost_exists(domain)
        result = strategy.request_certificate(domain)

        if %w[requested success].include?(result[:status])
          logger.info 'Created vhost', domain: domain.display_domain

          # Store the vhost data if returned and persistence is enabled
          if @persist && result[:data]
            domain.vhost   = result[:data].to_json
            domain.updated = OT.now.to_i
            domain.save
          end
        else
          logger.warn 'Failed to create vhost',
            domain: domain.display_domain,
            message: result[:message]
        end
      rescue StandardError => ex
        logger.error 'Error creating vhost',
          domain: domain.display_domain,
          error: ex.message
      end

      # Persist verification changes to the domain
      #
      # @param domain [Onetime::CustomDomain]
      # @param dns_result [Hash]
      # @param status_result [Hash]
      # @return [Boolean] Whether changes were saved
      def persist_changes(domain, dns_result, status_result)
        # Update verification status
        domain.verified! dns_result[:validated] unless dns_result[:validated].nil?

        # Update vhost data if present
        domain.vhost = status_result[:data].to_json if status_result[:data]

        # Update resolving status
        unless status_result[:is_resolving].nil?
          domain.resolving = status_result[:is_resolving].to_s
        end

        domain.updated = OT.now.to_i
        domain.save

        true
      rescue StandardError => ex
        logger.error 'Failed to persist changes',
          domain: domain.display_domain,
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
