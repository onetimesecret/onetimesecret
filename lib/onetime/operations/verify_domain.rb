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
    #   result.ssl_ready      # => true/false/nil
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
        :dns_indeterminate, # Boolean: the TXT check produced no answer; verified left untouched
        :dns_message,     # String or nil: strategy's description of the TXT outcome
        :override_held,   # Boolean: TXT check failed but an operator override kept verified
        :ssl_ready,       # Boolean or nil: has valid SSL certificate; nil means unknown
        :is_resolving,    # Boolean or nil: DNS resolving to correct target; nil means unknown
        :persisted,       # Boolean: changes were saved
        :error,           # String or nil: error message if failed
      ) do
        def initialize(dns_indeterminate: false, dns_message: nil, override_held: false, **)
          super
        end

        def success?
          error.nil?
        end

        # One label for the TXT outcome, for operator-facing output.
        # @return [Symbol] :validated, :indeterminate, :override_held, :failed
        def dns_outcome
          return :validated if dns_validated
          return :indeterminate if dns_indeterminate

          override_held ? :override_held : :failed
        end

        # The domain lost :verified on this run (the signature of the SSO
        # breakage incidents: verified gates every auth URL).
        def demoted?
          previous_state == :verified && current_state != :verified
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
            dns_indeterminate: dns_indeterminate,
            dns_message: dns_message,
            dns_outcome: dns_outcome,
            override_held: override_held,
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
        :indeterminate_count, # Integer: domains whose TXT check produced no answer
        :demoted_count,   # Integer: domains that lost :verified on this run
        :results,         # Array<Result>: individual results
        :duration_seconds, # Float: total processing time
      ) do
        def initialize(indeterminate_count: 0, demoted_count: 0, **)
          super
        end

        def success?
          failed_count == 0
        end

        def to_h
          {
            total: total,
            verified_count: verified_count,
            failed_count: failed_count,
            skipped_count: skipped_count,
            indeterminate_count: indeterminate_count,
            demoted_count: demoted_count,
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
        # Always persist when @persist is true - the validation results determine
        # WHAT we persist (verified/unverified), not WHETHER we persist
        persisted = false
        if @persist
          persisted = persist_changes(domain, dns_result, status_result)
        end

        current_state = domain.verification_state

        # Auto-fetch the domain's favicon on the transition INTO :verified. Fires
        # only when the domain first reaches :verified — not on every re-verify of
        # an already-verified domain — so periodic domain_refresh runs don't re-queue.
        # This path covers both the API verify and the scheduled domain_refresh_job,
        # since both route through verify_single. (#3780)
        if current_state == :verified && previous_state != :verified
          enqueue_favicon_fetch(domain)
        end

        result = Result.new(
          domain: domain,
          previous_state: previous_state,
          current_state: current_state,
          dns_validated: dns_result[:validated] || false,
          dns_indeterminate: dns_result[:indeterminate] == true,
          dns_message: dns_result[:message],
          override_held: override_held?(domain, dns_result),
          ssl_ready: status_result[:has_ssl],
          is_resolving: status_result[:is_resolving],
          persisted: persisted,
          error: nil,
        )

        log_notable_outcome(result, dns_result)
        result
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
          ssl_ready: nil,
          is_resolving: nil,
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
          indeterminate_count: results.count { |r| r.dns_indeterminate },
          demoted_count: results.count { |r| r.demoted? },
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

      # Warn on the two outcomes an operator needs to find without a console
      # session: an indeterminate TXT check (verified left untouched) and a
      # demotion out of :verified. The raw strategy payload rides along so the
      # failure modes can be told apart from the log line alone.
      #
      # @param result [Result]
      # @param dns_result [Hash]
      def log_notable_outcome(result, dns_result)
        if result.override_held
          logger.info 'DNS validation failed; verified held by operator override',
            domain: result.domain.display_domain,
            message: dns_result[:message]
        end

        if result.dns_indeterminate
          logger.warn 'DNS validation indeterminate; verified left unchanged',
            domain: result.domain.display_domain,
            state: result.current_state,
            message: dns_result[:message],
            data: dns_result[:data]
        end

        return unless result.demoted?

        logger.warn 'Domain demoted from verified',
          domain: result.domain.display_domain,
          previous_state: result.previous_state,
          current_state: result.current_state,
          dns_validated: result.dns_validated,
          is_resolving: result.is_resolving,
          message: dns_result[:message],
          data: dns_result[:data]
      end

      # Check SSL and resolution status
      #
      # @param domain [Onetime::CustomDomain]
      # @return [Hash] { ready: Boolean, has_ssl: Boolean/nil, is_resolving: Boolean/nil, ... }
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
        { ready: false, has_ssl: nil, is_resolving: nil, message: ex.message }
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

      # Persist verification changes to the domain.
      #
      # Atomic update: persist a field only when the originating call returned
      # authoritative data. Mixing stale and fresh state caused issue #3080
      # (vhost stayed green while resolving flipped to "false" on API failure).
      #
      # Fresh-data indicators:
      #   :data present — active strategy returned a payload (Approximated 200,
      #                   or the Caddy on-demand probe with a known has_ssl)
      #   :mode present — the strategy's own answer, no provider call to fail
      #
      # Status has two nil-guards. `resolving` is skipped here when
      # :is_resolving is nil. has_ssl has no field of its own: it is stored
      # inside the `vhost` blob, so a strategy that does not know it must
      # leave :data out (CaddyOnDemandStrategy#check_status does). A status
      # result with neither :data nor :mode changes nothing and records the
      # failed check in vhost_fetch_failed_at.
      #
      # A 200 is not enough for `verified`: the strategy returns validated: nil
      # when the upstream checker answered but its own DNS lookup failed
      # (indeterminate). That is not evidence about the customer's DNS, so the
      # stored flag is left alone — neither promoted nor demoted.
      #
      # @param domain [Onetime::CustomDomain]
      # @param dns_result [Hash]
      # @param status_result [Hash]
      # @return [Boolean] Whether changes were saved
      def persist_changes(domain, dns_result, status_result)
        if (dns_result[:data] || dns_result[:mode]) && !dns_result[:validated].nil? &&
           !override_held?(domain, dns_result)
          domain.verified! dns_result[:validated]
          # DNS has now proven ownership itself; the operator's assertion is
          # no longer what holds the flag, so later failures demote normally.
          domain.verified_by_override = false if dns_result[:validated]
        end

        if status_result[:data] || status_result[:mode]
          domain.vhost                 = status_result[:data].to_json if status_result[:data]
          unless status_result[:is_resolving].nil?
            domain.resolving = status_result[:is_resolving]
          end
          domain.vhost_fetch_failed_at = nil
        else
          domain.vhost_fetch_failed_at = OT.now.to_i
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

      # A Colonel override is an operator's standing assertion of ownership for
      # domains DNS checks cannot reach (private networks, a broken upstream
      # checker). A failed check must not undo it on the next refresh run; only
      # the operator (override to false) or a passing check clears it.
      #
      # @param domain [Onetime::CustomDomain]
      # @param dns_result [Hash]
      # @return [Boolean]
      def override_held?(domain, dns_result)
        dns_result[:validated] == false && domain.verified_by_override == true
      end

      # Enqueue a background favicon fetch for a freshly-verified domain.
      #
      # Gated by the jobs.favicon_fetch.enabled feature flag (default off) and
      # fully isolated: any failure here is logged and swallowed so it can never
      # break verification. When jobs are disabled the Publisher runs the fetch
      # operation inline; either way this call must not raise.
      #
      # @param domain [Onetime::CustomDomain]
      def enqueue_favicon_fetch(domain)
        return unless OT.conf.dig('jobs', 'favicon_fetch', 'enabled') == true

        Onetime::Jobs::Publisher.enqueue_favicon_fetch(domain.identifier)
      rescue StandardError => ex
        logger.error 'Failed to enqueue favicon fetch',
          domain: domain&.display_domain,
          error: ex.message,
          error_class: ex.class.name
      end

      # @return [SemanticLogger::Logger] Logger instance
      def logger
        @logger ||= Onetime.get_logger('Operations')
      end
    end
  end
end
