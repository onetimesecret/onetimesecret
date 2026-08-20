# lib/onetime/domain_validation/sender_strategies/base_strategy.rb
#
# frozen_string_literal: true

require 'resolv'
require 'concurrent'
require 'json'
require_relative '../../utils/retry_helper'
require_relative '../record_matcher'

module Onetime
  module DomainValidation
    module SenderStrategies
      # BaseStrategy - Interface for sender domain VERIFICATION strategies.
      #
      # This is the VERIFICATION layer: verify_dns_records returns a :verified
      # boolean per record and sets mailer_config.verification_status.
      #
      # For FACT-FINDING (dns_exists, value_matches without status determination),
      # see Mail::SenderStrategies::BaseSenderStrategy#check_dns_records instead.
      #
      # For PROVISIONING (create domain at provider, get DNS records to configure),
      # see Mail::SenderStrategies::*SenderStrategy#provision_dns_records instead.
      #
      # Used by: ValidateSenderDomain operation -> DomainValidationWorker
      #
      # Each provider strategy (SES, SendGrid, Lettermint) implements these
      # methods to generate the DNS records a customer must configure and to
      # verify those records via live DNS lookups.
      #
      # The mailer_config argument carries provider credentials and a domain_id
      # foreign key. The sender domain for DNS record generation and verification
      # is extracted from mailer_config.from_address.
      #
      class BaseStrategy
        include Onetime::Utils::RetryHelper

        # Default TTL for DNS cache entries (10 minutes)
        DNS_CACHE_TTL = 600

        # DNS retry configuration for transient failures
        DNS_RETRY_MAX        = 2
        DNS_RETRY_BASE_DELAY = 0.5

        # Predicate for retriable DNS errors (timeouts only, not NXDOMAIN)
        DNS_RETRIABLE = ->(ex) { ex.is_a?(Resolv::ResolvTimeout) }

        # Returns the keyword arguments accepted by this strategy's constructor.
        # Subclasses override to declare their options (e.g. [:region]).
        # The factory uses this to validate options before splatting.
        #
        # @return [Array<Symbol>] Accepted keyword argument names
        def self.accepted_options
          [].freeze
        end

        # Returns the DNS records the customer must configure for this provider.
        #
        # Reads provisioned records from mailer_config.dns_records.value
        # (array of string-keyed hashes stored from the provider API) and
        # maps them to the validation format with symbol keys. Purpose
        # classification is delegated to the per-provider
        # #classify_record_purpose hook.
        #
        # Advisory records ('optional' => true, e.g. SMTP2GO tracking, SES
        # DMARC) are excluded so they never gate verification — the same
        # discipline as Mail::SenderStrategies::BaseSenderStrategy
        # #check_dns_records. Display paths read
        # MailerConfig#required_dns_records, which still includes them.
        #
        # Returns an empty array if no provisioned records exist — does
        # NOT fall back to hardcoded selectors.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>] Each hash contains:
        #   - :type [String] Record type (TXT, CNAME, MX)
        #   - :host [String] DNS hostname to create
        #   - :value [String] Expected record value
        #   - :purpose [String] Human-readable description (e.g. "DKIM", "SPF")
        #
        def required_dns_records(mailer_config)
          provisioned = mailer_config.dns_records&.value

          if provisioned.nil? || provisioned.empty?
            logger.error "[#{strategy_name}-validation] No provisioned DNS records for #{mailer_config.domain_id}; cannot validate"
            return []
          end

          required = provisioned.reject { |r| [true, 'true'].include?(r['optional']) }

          required.map do |record|
            {
              type: record['type'].to_s.upcase,
              host: record['name'].to_s,
              value: record['value'].to_s,
              purpose: classify_record_purpose(record),
            }
          end
        end

        # Queries live DNS and compares against expected records.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @param bypass_cache [Boolean] Skip cache read/write when true
        # @return [Array<Hash>] Each hash contains:
        #   - :type [String] Record type (TXT, CNAME, MX)
        #   - :host [String] DNS hostname queried
        #   - :expected [String] Expected value
        #   - :actual [Array<String>] Values found in DNS
        #   - :verified [Boolean] Whether a match was found
        #   - :purpose [String] Human-readable description
        #
        def verify_dns_records(mailer_config, bypass_cache: false)
          raise NotImplementedError, "#{self.class} must implement #verify_dns_records"
        end

        # Returns the strategy name for logging and debugging.
        #
        # @return [String] Strategy identifier (e.g. "ses", "sendgrid")
        #
        def strategy_name
          self.class.name.split('::').last.sub('Validation', '').downcase
        end

        private

        def logger
          @logger ||= Onetime.get_logger('SenderStrategies')
        end

        # Per-provider hook for #required_dns_records: infer a
        # human-readable purpose (e.g. "DKIM", "SPF") for a provisioned
        # record.
        #
        # @param record [Hash] String-keyed hash from provisioned dns_records
        # @return [String]
        #
        def classify_record_purpose(record)
          raise NotImplementedError, "#{self.class} must implement #classify_record_purpose"
        end

        # Resolve the sender domain from mailer_config's from_address.
        #
        # The sender domain (where email originates) is distinct from
        # display_domain (where OTS secrets are hosted). DNS records for
        # email authentication must match the sender domain.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [String] The sender domain (e.g. "example.com")
        # @raise [ArgumentError] If from_address is missing or invalid
        #
        def resolve_domain(mailer_config)
          from_address = mailer_config.from_address.to_s
          unless from_address.include?('@')
            raise ArgumentError,
              "MailerConfig #{mailer_config.domain_id} has no valid from_address"
          end

          domain = from_address.split('@').last.to_s
          if domain.empty?
            raise ArgumentError,
              "MailerConfig #{mailer_config.domain_id} has empty domain in from_address"
          end

          logger.debug 'Resolved sender domain from from_address',
            sender_domain: domain,
            from_address: from_address,
            mailer_config_id: mailer_config.domain_id

          domain
        end

        # Query TXT records for a hostname.
        #
        # Checks Redis cache first; on miss, performs live DNS lookup with
        # retry logic for transient failures. Caches the result with
        # DNS_CACHE_TTL. Empty results are cached to prevent repeated
        # lookups for non-existent records.
        #
        # Retry behavior:
        # - Retries on Resolv::ResolvTimeout (transient network issues)
        # - Does NOT retry on Resolv::ResolvError (authoritative "not found")
        #
        # @param hostname [String] Fully qualified hostname
        # @param resolver [Resolv::DNS] Optional resolver instance
        # @param bypass_cache [Boolean] Skip cache read/write when true
        # @return [Array] Tuple of [Array<String>, String|nil] - [values, error_type]
        #
        def lookup_txt_records(hostname, resolver: nil, bypass_cache: false)
          unless bypass_cache
            cached = fetch_from_cache(hostname, 'TXT')
            return [cached, nil] if cached
          end

          dns = resolver || Resolv::DNS.new

          values = with_retry(
            max_retries: DNS_RETRY_MAX,
            base_delay: DNS_RETRY_BASE_DELAY,
            retriable: DNS_RETRIABLE,
            logger: logger,
            context: "TXT lookup #{hostname}",
          ) do
            resources = dns.getresources(hostname, Resolv::DNS::Resource::IN::TXT)
            resources.map { |r| r.strings.join }
          end

          store_in_cache(hostname, 'TXT', values) unless bypass_cache
          [values, nil]
        rescue Resolv::ResolvError, Resolv::ResolvTimeout => ex
          logger.debug "[SenderStrategies] TXT lookup failed for #{hostname}: #{ex.message}"
          [[], classify_dns_error(ex)]
        ensure
          dns&.close unless resolver
        end

        # Query CNAME records for a hostname.
        #
        # Checks Redis cache first; on miss, performs live DNS lookup with
        # retry logic for transient failures. Caches the result with
        # DNS_CACHE_TTL. Empty results are cached to prevent repeated
        # lookups for non-existent records.
        #
        # Retry behavior:
        # - Retries on Resolv::ResolvTimeout (transient network issues)
        # - Does NOT retry on Resolv::ResolvError (authoritative "not found")
        #
        # @param hostname [String] Fully qualified hostname
        # @param resolver [Resolv::DNS] Optional resolver instance
        # @param bypass_cache [Boolean] Skip cache read/write when true
        # @return [Array] Tuple of [Array<String>, String|nil] - [values, error_type]
        #
        def lookup_cname_records(hostname, resolver: nil, bypass_cache: false)
          unless bypass_cache
            cached = fetch_from_cache(hostname, 'CNAME')
            return [cached, nil] if cached
          end

          dns = resolver || Resolv::DNS.new

          values = with_retry(
            max_retries: DNS_RETRY_MAX,
            base_delay: DNS_RETRY_BASE_DELAY,
            retriable: DNS_RETRIABLE,
            logger: logger,
            context: "CNAME lookup #{hostname}",
          ) do
            resources = dns.getresources(hostname, Resolv::DNS::Resource::IN::CNAME)
            resources.map { |r| r.name.to_s }
          end

          store_in_cache(hostname, 'CNAME', values) unless bypass_cache
          [values, nil]
        rescue Resolv::ResolvError, Resolv::ResolvTimeout => ex
          logger.debug "[SenderStrategies] CNAME lookup failed for #{hostname}: #{ex.message}"
          [[], classify_dns_error(ex)]
        ensure
          dns&.close unless resolver
        end

        # Query MX records for a hostname.
        #
        # Checks Redis cache first; on miss, performs live DNS lookup with
        # retry logic for transient failures. Caches the result with
        # DNS_CACHE_TTL. Empty results are cached to prevent repeated
        # lookups for non-existent records.
        #
        # Retry behavior:
        # - Retries on Resolv::ResolvTimeout (transient network issues)
        # - Does NOT retry on Resolv::ResolvError (authoritative "not found")
        #
        # @param hostname [String] Fully qualified hostname
        # @param resolver [Resolv::DNS] Optional resolver instance
        # @param bypass_cache [Boolean] Skip cache read/write when true
        # @return [Array] Tuple of [Array<String>, String|nil] - [values, error_type]
        #
        def lookup_mx_records(hostname, resolver: nil, bypass_cache: false)
          unless bypass_cache
            cached = fetch_from_cache(hostname, 'MX')
            return [cached, nil] if cached
          end

          dns = resolver || Resolv::DNS.new

          values = with_retry(
            max_retries: DNS_RETRY_MAX,
            base_delay: DNS_RETRY_BASE_DELAY,
            retriable: DNS_RETRIABLE,
            logger: logger,
            context: "MX lookup #{hostname}",
          ) do
            resources = dns.getresources(hostname, Resolv::DNS::Resource::IN::MX)
            resources.map { |r| r.exchange.to_s }
          end

          store_in_cache(hostname, 'MX', values) unless bypass_cache
          [values, nil]
        rescue Resolv::ResolvError, Resolv::ResolvTimeout => ex
          logger.debug "[SenderStrategies] MX lookup failed for #{hostname}: #{ex.message}"
          [[], classify_dns_error(ex)]
        ensure
          dns&.close unless resolver
        end

        # Check whether the expected value appears in the actual DNS results.
        #
        # The matching discipline lives in RecordMatcher, shared with the
        # Mail fact-finding pipeline (issue #4047). TXT dispatch goes
        # through the instance method so per-strategy overrides (and
        # instrumentation) keep working.
        #
        # @param type [String] Record type
        # @param expected [String] Expected value
        # @param actual_values [Array<String>] DNS results
        # @return [Boolean]
        #
        def record_matches?(type, expected, actual_values)
          return txt_record_matches?(expected.to_s.strip, actual_values) if type == 'TXT'

          RecordMatcher.record_matches?(type, expected, actual_values)
        end

        # Check whether a TXT record matches expected value.
        # See RecordMatcher#txt_record_matches? for the dispatch discipline.
        # SPF dispatch goes through the instance method (see record_matches?).
        #
        # @param expected [String] Expected value, trimmed
        # @param actual_values [Array<String>] DNS results
        # @return [Boolean]
        #
        def txt_record_matches?(expected, actual_values)
          return spf_record_matches?(expected.downcase, actual_values) if RecordNormalizer.spf?(expected)

          RecordMatcher.txt_record_matches?(expected, actual_values)
        end

        # Check whether an SPF record matches expected value.
        # See RecordMatcher#spf_record_matches? for the include: semantics.
        #
        # @param normalized_expected [String] Downcased expected SPF value
        # @param actual_values [Array<String>] DNS results
        # @return [Boolean]
        #
        def spf_record_matches?(normalized_expected, actual_values)
          RecordMatcher.spf_record_matches?(normalized_expected, actual_values)
        end

        # Run verification for all required records using per-thread resolvers.
        #
        # Performs DNS lookups in parallel using Concurrent::Promises. Each
        # record verification runs in its own thread with its own resolver,
        # reducing total latency from O(n * timeout) to O(timeout) for n records.
        # Each thread manages its own resolver lifecycle to avoid cleanup issues
        # with shared resources in the thread pool.
        #
        # Uses pipelined Redis operations to batch-fetch cached values before
        # DNS lookups and batch-store results after lookups complete.
        #
        # Concrete strategies can call this from verify_dns_records to avoid
        # duplicating the resolver lifecycle.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @param bypass_cache [Boolean] Skip cache read/write when true
        # @return [Array<Hash>] Verification results in same order as input
        #
        def verify_all_records(mailer_config, bypass_cache: false)
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          records    = required_dns_records(mailer_config)

          # Batch-fetch all cache entries in a single Redis round-trip
          cached_values = bypass_cache ? {} : fetch_cache_bulk(records)

          # Launch parallel lookups; each future manages its own resolver lifecycle
          futures = records.map do |record|
            cache_key = dns_cache_key(record[:host], record[:type])
            cached    = cached_values[cache_key]

            Concurrent::Promises.future do
              local_resolver = Resolv::DNS.new
              verify_record_with_cache(
                record,
                resolver: local_resolver,
                cached_value: cached,
                bypass_cache: bypass_cache,
              )
            rescue StandardError => ex
              # Return a failed verification result rather than crashing
              logger.warn "[SenderStrategies] Record verification failed for #{record[:host]}: #{ex.message}"
              {
                type: record[:type],
                host: record[:host],
                expected: record[:value],
                actual: [],
                verified: false,
                purpose: record[:purpose],
                error: ex.message,
                error_type: classify_dns_error(ex),
              }
            ensure
              local_resolver&.close
            end
          end

          # Collect results preserving input order
          results = futures.map(&:value!)

          # Batch-store results that required DNS lookups (not from cache)
          unless bypass_cache
            store_results = results.reject { |r| r[:from_cache] }
            store_cache_bulk(store_results) unless store_results.empty?
          end

          # Remove internal :from_cache flag before returning
          results.each { |r| r.delete(:from_cache) }

          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
          OT.info '[DNS] verify_all_records completed', duration_ms: duration_ms, record_count: records.size

          results
        end

        # Verify a single record, using a pre-fetched cached value if available.
        #
        # Both branches evaluate the full record set (selection + matching),
        # so a cache hit can also surface 'ambiguous_record_set'.
        #
        # @param record [Hash] A record hash from required_dns_records
        # @param resolver [Resolv::DNS] Shared resolver instance
        # @param cached_value [Array<String>, nil] Pre-fetched cache value or nil
        # @param bypass_cache [Boolean] Skip cache when true
        # @return [Hash] Verification result with :from_cache flag and optional :error_type
        #
        def verify_record_with_cache(record, resolver:, cached_value:, bypass_cache:)
          if cached_value && !bypass_cache
            verified, match_error = evaluate_record_set(record, cached_value)
            result                = {
              type: record[:type],
              host: record[:host],
              expected: record[:value],
              actual: cached_value,
              verified: verified,
              purpose: record[:purpose],
              from_cache: true,
            }
            result[:error_type]   = match_error if match_error
            return result
          end

          # Perform live DNS lookup
          actual, error_type    = lookup_dns_by_type(record[:type], record[:host], resolver: resolver, bypass_cache: true)
          verified, match_error = evaluate_record_set(record, actual)

          result              = {
            type: record[:type],
            host: record[:host],
            expected: record[:value],
            actual: actual,
            verified: verified,
            purpose: record[:purpose],
            from_cache: false,
          }
          effective_error     = error_type || match_error
          result[:error_type] = effective_error if effective_error
          result
        end

        # Select the relevant records from the DNS result set, then match.
        #
        # RFC 7489 Section 6.6.3 (DMARC) and RFC 7208 Section 4.5 (SPF) both
        # require record-set selection before evaluation: filter the TXT set
        # by discriminator, discard unrelated records, and treat more than
        # one surviving record as an error — never a pass. A duplicate DMARC
        # or SPF record fails at receiving MTAs, so reporting it verified
        # would be a false green (issue #4023).
        #
        # @param record [Hash] A record hash from required_dns_records
        # @param actual_values [Array<String>] Full DNS result set
        # @return [Array(Boolean, String|nil)] [verified, error_type or nil]
        #
        def evaluate_record_set(record, actual_values)
          candidates, ambiguous = select_txt_record_set(record[:type], record[:value], actual_values)
          return [false, 'ambiguous_record_set'] if ambiguous

          [record_matches?(record[:type], record[:value], candidates), nil]
        end

        # Filter a TXT result set down to records relevant to the expected
        # value. See RecordMatcher#select_txt_record_set for the selection
        # rules and RFC references.
        #
        # @return [Array(Array<String>, Boolean)] [candidates, ambiguous]
        #
        def select_txt_record_set(type, expected, actual_values)
          RecordMatcher.select_txt_record_set(type, expected, actual_values)
        end

        # Lookup DNS records by type.
        #
        # @param type [String] Record type (TXT, CNAME, MX)
        # @param hostname [String] Hostname to query
        # @param resolver [Resolv::DNS] DNS resolver instance
        # @param bypass_cache [Boolean] Skip cache when true
        # @return [Array] Tuple of [Array<String>, String|nil] - [values, error_type]
        #
        def lookup_dns_by_type(type, hostname, resolver:, bypass_cache:)
          case type
          when 'TXT'
            lookup_txt_records(hostname, resolver: resolver, bypass_cache: bypass_cache)
          when 'CNAME'
            lookup_cname_records(hostname, resolver: resolver, bypass_cache: bypass_cache)
          when 'MX'
            lookup_mx_records(hostname, resolver: resolver, bypass_cache: bypass_cache)
          else
            [[], nil]
          end
        end

        # Generate a Redis cache key for DNS lookups.
        #
        # Normalizes hostname by downcasing and stripping trailing dots to
        # prevent cache fragmentation between "example.com" and "example.com."
        #
        # @param hostname [String] Fully qualified hostname
        # @param record_type [String] DNS record type (TXT, CNAME, MX)
        # @return [String] Redis key in format "dns:cache:{hostname}:{type}"
        #
        def dns_cache_key(hostname, record_type)
          "dns:cache:#{hostname.to_s.downcase.chomp('.')}:#{record_type.to_s.downcase}"
        end

        # Check cache for DNS lookup result.
        #
        # @param hostname [String] Fully qualified hostname
        # @param record_type [String] DNS record type
        # @return [Array<String>, nil] Cached values or nil if not cached
        #
        def fetch_from_cache(hostname, record_type)
          key    = dns_cache_key(hostname, record_type)
          cached = redis.get(key)
          return nil unless cached

          JSON.parse(cached)
        rescue JSON::ParserError => ex
          logger.debug "[SenderStrategies] Cache parse error for #{key}: #{ex.message}"
          nil
        rescue StandardError => ex
          # Cache failures should not break DNS lookups
          logger.debug "[SenderStrategies] Cache fetch error: #{ex.message}"
          nil
        end

        # Store DNS lookup result in cache.
        #
        # @param hostname [String] Fully qualified hostname
        # @param record_type [String] DNS record type
        # @param values [Array<String>] Record values to cache (may be empty)
        # @param ttl [Integer] Cache TTL in seconds (default: DNS_CACHE_TTL)
        # @return [void]
        #
        def store_in_cache(hostname, record_type, values, ttl: DNS_CACHE_TTL)
          key = dns_cache_key(hostname, record_type)
          redis.setex(key, ttl, JSON.generate(values))
        rescue StandardError => ex
          # Cache failures should not break DNS lookups
          logger.debug "[SenderStrategies] Cache store error for #{key}: #{ex.message}"
        end

        # Batch-fetch multiple DNS cache entries in a single Redis round-trip.
        #
        # Uses pipelining to reduce latency when checking cache for multiple
        # records before performing DNS lookups.
        #
        # @param records [Array<Hash>] Records with :host and :type keys
        # @return [Hash<String, Array<String>>] Map of cache key to parsed values
        #
        def fetch_cache_bulk(records)
          return {} if records.empty?

          keys = records.map { |r| dns_cache_key(r[:host], r[:type]) }

          # Pipeline GET operations
          cached_values = redis.pipelined do |pipe|
            keys.each { |k| pipe.get(k) }
          end

          # Build result hash, parsing JSON and filtering out misses
          result = {}
          keys.each_with_index do |key, idx|
            raw = cached_values[idx]
            next unless raw

            begin
              result[key] = JSON.parse(raw)
            rescue JSON::ParserError => ex
              logger.debug "[SenderStrategies] Bulk cache parse error for #{key}: #{ex.message}"
            end
          end

          result
        rescue StandardError => ex
          # Cache failures should not break DNS lookups
          logger.debug "[SenderStrategies] Bulk cache fetch error: #{ex.message}"
          {}
        end

        # Batch-store multiple DNS results in a single Redis round-trip.
        #
        # Uses pipelining to reduce latency when caching multiple DNS lookup
        # results after parallel verification.
        #
        # @param results [Array<Hash>] Verification results with :host, :type, :actual
        # @param ttl [Integer] Cache TTL in seconds (default: DNS_CACHE_TTL)
        # @return [void]
        #
        def store_cache_bulk(results, ttl: DNS_CACHE_TTL)
          return if results.empty?

          redis.pipelined do |pipe|
            results.each do |r|
              key = dns_cache_key(r[:host], r[:type])
              pipe.setex(key, ttl, JSON.generate(r[:actual]))
            end
          end
        rescue StandardError => ex
          # Cache failures should not break DNS lookups
          logger.debug "[SenderStrategies] Bulk cache store error: #{ex.message}"
        end

        # Access to Redis connection via CustomDomain's dbclient.
        # Consistent with DnsRateLimiter pattern.
        #
        # @return [Redis] Redis client instance
        #
        def redis
          Onetime::CustomDomain.dbclient
        end

        # Classify a DNS exception into an error type string.
        #
        # Used to provide structured error information in verification results,
        # allowing consumers to distinguish between transient failures (timeouts)
        # and authoritative failures (not found).
        #
        # @param exception [StandardError] The caught exception
        # @return [String] One of 'timeout', 'not_found', or 'network_error'
        #
        def classify_dns_error(exception)
          case exception
          when Resolv::ResolvTimeout then 'timeout'
          when Resolv::ResolvError then 'not_found'
          else 'network_error'
          end
        end
      end
    end
  end
end
