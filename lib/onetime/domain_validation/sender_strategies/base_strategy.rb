# lib/onetime/domain_validation/sender_strategies/base_strategy.rb
#
# frozen_string_literal: true

require 'resolv'
require 'concurrent'
require 'json'
require_relative '../../utils/retry_helper'

module Onetime
  module DomainValidation
    module SenderStrategies
      # BaseStrategy - Interface for sender domain validation strategies.
      #
      # Each provider strategy (SES, SendGrid, Lettermint) implements these
      # methods to generate the DNS records a customer must configure and to
      # verify those records via live DNS lookups.
      #
      # The mailer_config argument carries provider credentials and a domain_id
      # foreign key. The associated CustomDomain's display_domain is the domain
      # name used in record generation and verification.
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
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [Array<Hash>] Each hash contains:
        #   - :type [String] Record type (TXT, CNAME, MX)
        #   - :host [String] DNS hostname to create
        #   - :value [String] Expected record value
        #   - :purpose [String] Human-readable description (e.g. "DKIM", "SPF")
        #
        def required_dns_records(mailer_config)
          raise NotImplementedError, "#{self.class} must implement #required_dns_records"
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

        # Resolve the display_domain from a mailer_config's associated CustomDomain.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @return [String] The domain name (e.g. "secrets.example.com")
        # @raise [ArgumentError] If the domain cannot be resolved
        #
        def resolve_domain(mailer_config)
          custom_domain = mailer_config.custom_domain
          unless custom_domain
            raise ArgumentError,
              "MailerConfig #{mailer_config.domain_id} has no associated CustomDomain"
          end

          domain = custom_domain.display_domain.to_s
          if domain.empty?
            raise ArgumentError,
              "CustomDomain #{custom_domain.identifier} has no display_domain"
          end

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
        # @return [Array<String>] TXT record values found
        #
        def lookup_txt_records(hostname, resolver: nil, bypass_cache: false)
          unless bypass_cache
            cached = fetch_from_cache(hostname, 'TXT')
            return cached if cached
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
          values
        rescue Resolv::ResolvError => ex
          # Authoritative "not found" - do not retry, return empty
          logger.debug "[SenderStrategies] TXT lookup failed for #{hostname}: #{ex.message}"
          []
        rescue Resolv::ResolvTimeout => ex
          # Timeout after all retries exhausted
          logger.debug "[SenderStrategies] TXT lookup timed out for #{hostname}: #{ex.message}"
          []
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
        # @return [Array<String>] CNAME target values found
        #
        def lookup_cname_records(hostname, resolver: nil, bypass_cache: false)
          unless bypass_cache
            cached = fetch_from_cache(hostname, 'CNAME')
            return cached if cached
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
          values
        rescue Resolv::ResolvError => ex
          # Authoritative "not found" - do not retry, return empty
          logger.debug "[SenderStrategies] CNAME lookup failed for #{hostname}: #{ex.message}"
          []
        rescue Resolv::ResolvTimeout => ex
          # Timeout after all retries exhausted
          logger.debug "[SenderStrategies] CNAME lookup timed out for #{hostname}: #{ex.message}"
          []
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
        # @return [Array<String>] MX exchange hostnames found
        #
        def lookup_mx_records(hostname, resolver: nil, bypass_cache: false)
          unless bypass_cache
            cached = fetch_from_cache(hostname, 'MX')
            return cached if cached
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
          values
        rescue Resolv::ResolvError => ex
          # Authoritative "not found" - do not retry, return empty
          logger.debug "[SenderStrategies] MX lookup failed for #{hostname}: #{ex.message}"
          []
        rescue Resolv::ResolvTimeout => ex
          # Timeout after all retries exhausted
          logger.debug "[SenderStrategies] MX lookup timed out for #{hostname}: #{ex.message}"
          []
        ensure
          dns&.close unless resolver
        end

        # Verify a single DNS record by comparing expected value against live DNS.
        #
        # Uses a shared resolver to avoid opening/closing connections per record.
        #
        # @param record [Hash] A record hash from required_dns_records
        # @param resolver [Resolv::DNS] Shared resolver instance
        # @param bypass_cache [Boolean] Skip cache read/write when true
        # @return [Hash] Verification result
        #
        def verify_record(record, resolver:, bypass_cache: false)
          actual = case record[:type]
                   when 'TXT'
                     lookup_txt_records(record[:host], resolver: resolver, bypass_cache: bypass_cache)
                   when 'CNAME'
                     lookup_cname_records(record[:host], resolver: resolver, bypass_cache: bypass_cache)
                   when 'MX'
                     lookup_mx_records(record[:host], resolver: resolver, bypass_cache: bypass_cache)
                   else
                     []
                   end

          verified = record_matches?(record[:type], record[:value], actual)

          {
            type: record[:type],
            host: record[:host],
            expected: record[:value],
            actual: actual,
            verified: verified,
            purpose: record[:purpose],
          }
        end

        # Check whether the expected value appears in the actual DNS results.
        #
        # For TXT/SPF records: customers commonly merge multiple provider
        # includes into one SPF record (e.g., "v=spf1 include:amazonses.com
        # include:sendgrid.net ~all"). We extract the include: directive from
        # the expected value and check that it appears in any actual TXT record
        # that starts with "v=spf1". For non-SPF TXT records, full substring
        # match is used.
        #
        # For CNAME and MX records: exact match after downcasing and stripping
        # trailing dots.
        #
        # @param type [String] Record type
        # @param expected [String] Expected value
        # @param actual_values [Array<String>] DNS results
        # @return [Boolean]
        #
        def record_matches?(type, expected, actual_values)
          normalized_expected = expected.to_s.downcase.chomp('.')

          case type
          when 'TXT'
            if normalized_expected.start_with?('v=spf1')
              # Extract the include: directive and verify it appears in an
              # actual SPF record, regardless of other mechanisms present
              spf_include = normalized_expected[/include:\S+/]
              if spf_include
                actual_values.any? do |v|
                  downcased = v.downcase
                  downcased.start_with?('v=spf1') && downcased.include?(spf_include)
                end
              else
                actual_values.any? { |v| v.downcase.include?(normalized_expected) }
              end
            else
              actual_values.any? { |v| v.downcase.include?(normalized_expected) }
            end
          when 'CNAME', 'MX'
            actual_values.any? { |v| v.downcase.chomp('.') == normalized_expected }
          else
            false
          end
        end

        # Run verification for all required records using per-thread resolvers.
        #
        # Performs DNS lookups in parallel using Concurrent::Promises. Each
        # record verification runs in its own thread with its own resolver,
        # reducing total latency from O(n * timeout) to O(timeout) for n records.
        # Each thread manages its own resolver lifecycle to avoid cleanup issues
        # with shared resources in the thread pool.
        #
        # Concrete strategies can call this from verify_dns_records to avoid
        # duplicating the resolver lifecycle.
        #
        # @param mailer_config [Onetime::CustomDomain::MailerConfig]
        # @param bypass_cache [Boolean] Skip cache read/write when true
        # @return [Array<Hash>] Verification results in same order as input
        #
        def verify_all_records(mailer_config, bypass_cache: false)
          records = required_dns_records(mailer_config)

          # Launch parallel lookups; each future manages its own resolver lifecycle
          futures = records.map do |record|
            Concurrent::Promises.future do
              local_resolver = Resolv::DNS.new
              verify_record(record, resolver: local_resolver, bypass_cache: bypass_cache)
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
              }
            ensure
              local_resolver&.close
            end
          end

          # Collect results preserving input order
          futures.map(&:value!)
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

        # Access to Redis connection via CustomDomain's dbclient.
        # Consistent with DnsRateLimiter pattern.
        #
        # @return [Redis] Redis client instance
        #
        def redis
          Onetime::CustomDomain.dbclient
        end
      end
    end
  end
end
