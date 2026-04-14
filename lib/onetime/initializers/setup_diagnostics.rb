# lib/onetime/initializers/setup_diagnostics.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # SetupDiagnostics initializer
    #
    # Configures Sentry error tracking and performance monitoring if diagnostics
    # are enabled. Sets up breadcrumbs logging, sampling rates, and environment
    # information for error context.
    #
    # Runtime state set:
    # - Onetime::Runtime.infrastructure.d9s_enabled
    #
    class SetupDiagnostics < Onetime::Boot::Initializer
      @depends_on = [:logging]
      @provides   = [:diagnostics]
      @optional   = true

      def execute(_context)
        d9s_enabled = OT.conf['diagnostics']['enabled'] || false

        unless d9s_enabled
          Onetime::Runtime.update_infrastructure(d9s_enabled: false)
          return
        end
        backend   = OT.conf['diagnostics']['sentry']['backend']
        dsn       = backend.fetch('dsn', nil)
        site_host = OT.conf.dig('site', 'host')

        OT.ld "[init] Setting up Sentry #{backend}..."

        # Log more details about the Sentry configuration for debugging
        OT.ld "[init] Sentry: DSN present: #{!dsn.nil?}"
        OT.ld "[init] Sentry: Site host: #{site_host.inspect}"
        OT.ld "[init] Sentry: OT.env: #{OT.env.inspect}"

        # Early validation to prevent nil errors during initialization
        if dsn.nil?
          OT.ld '[init] Sentry: Cannot initialize Sentry with nil DSN'
          d9s_enabled = false
        elsif site_host.nil?
          OT.le '[init] Sentry: Cannot initialize Sentry with nil site_host'
          OT.ld 'Falling back to default environment name'
          site_host = 'unknown-host'
        end

        # Only proceed if we have valid configuration
        unless d9s_enabled
          Onetime::Runtime.update_infrastructure(d9s_enabled: false)
          return
        end

        # Safely log first part of DSN for debugging
        dsn_preview = dsn ? "#{dsn[0..10]}..." : 'nil'
        OT.boot_logger.info "[init] Sentry: Initializing with DSN: #{dsn_preview}"

        # Only require Sentry if we have a DSN. We call explicitly
        # via Kernel to aid in testing.
        Kernel.require 'sentry-ruby'
        Kernel.require 'stackprof'

        Sentry.init do |config|
          config.dsn         = dsn
          config.environment = "#{site_host} (#{OT.env})"
          config.release     = OT::VERSION.details

          # Configure breadcrumbs logger for detailed error tracking.
          # Uses sentry_logger to capture progression of events leading
          # to errors, providing context for debugging.
          config.breadcrumbs_logger = [:sentry_logger]

          # Set traces_sample_rate to capture 10% of
          # transactions for performance monitoring.
          config.traces_sample_rate = 0.1

          # Set profiles_sample_rate to profile 10%
          # of sampled transactions.
          config.profiles_sample_rate = 0.1

          # Add a before_send to filter out problematic events and scrub sensitive URLs
          config.before_send = ->(event, _hint) do
            # Return nil if the event would cause errors in processing.
            return nil if event.nil?

            # Scrub sensitive URL paths and query parameters from event data.
            # This covers both event.request.url and custom context set via
            # scope.set_context('request', ...) in error handling middleware.
            Onetime::Initializers::SetupDiagnostics.scrub_event_urls(event)

            # Return the event if it passes validation
            event
          end
        end

        OT.ld "[init] Sentry: Status: #{Sentry.initialized? ? 'OK' : 'Failed'}"

        # Set runtime state
        Onetime::Runtime.update_infrastructure(d9s_enabled: true)
      end

      class << self
        # Distinguishes a verifiable identifier segment from a named path segment
        # (e.g. `/secret/IDENTIFIER` vs `/receipt/recent`).
        #
        # A base-36 verifiable identifier is always exactly 62 characters
        # (320 bits: 256-bit random + 64-bit HMAC tag), encoded with [0-9a-z].
        # Named segments are never this length, so length alone is a reliable
        # discriminant.
        #
        # Use {Familia::VerifiableIdentifier.plausible_identifier?} at route-matching
        # time - it checks length and character set without performing HMAC verification:
        #
        #   segment = request.path.split('/').last
        #   if Familia::VerifiableIdentifier.plausible_identifier?(segment)
        #     # route to resource handler
        #   else
        #     # route to named action
        #   end
        #
        # Use {Familia::VerifiableIdentifier.verified_identifier?} after routing, when
        # the identifier is about to authorize an operation. It runs the plausibility
        # check first, then verifies the embedded HMAC tag.
        #
        # For framework routers that require a pattern:
        #
        #   ID_LEN = Familia::SecureIdentifier.min_length_for_bits(320, 36) # => 62
        #   /\A[0-9a-z]{#{ID_LEN}}\z/
        #
        # Legacy v0.23 identifiers were 31 chars (base36). The minimum length check
        # (MIN_IDENTIFIER_LENGTH = 20) allows both formats while filtering out
        # named paths like "burn" or "recent".
        #
        # @see src/router/index.ts for frontend scrubbing via route metadata

        # Identifier length for v0.24+ VerifiableIdentifier (320 bits in base-36)
        IDENTIFIER_LENGTH = 62

        # Minimum identifier length to distinguish from named path segments.
        # Legacy v0.23 identifiers are 31 chars; this allows both old and new.
        MIN_IDENTIFIER_LENGTH = 20

        # Scrub sensitive data from URLs in Sentry events
        #
        # Handles two URL locations:
        # 1. event.request.url - Standard Sentry request data
        # 2. event.contexts['request']['url'] - Custom context set by error middleware
        #
        # @param event [Sentry::Event] The event to scrub
        # @return [Sentry::Event] The scrubbed event
        def scrub_event_urls(event)
          # Scrub standard request URL
          if event.request&.url
            original_url = event.request.url
            scrubbed_url = scrub_url(original_url)
            if scrubbed_url != original_url
              event.request.url = scrubbed_url
              OT.ld "[sentry] Scrubbed request.url"
            end
          end

          # Scrub custom request context URL (set via scope.set_context in error middleware)
          if event.contexts.is_a?(Hash) &&
             event.contexts['request'].is_a?(Hash) &&
             event.contexts['request']['url']
            original_url = event.contexts['request']['url']
            scrubbed_url = scrub_url(original_url)
            if scrubbed_url != original_url
              event.contexts['request']['url'] = scrubbed_url
              OT.ld "[sentry] Scrubbed contexts.request.url"
            end
          end

          event
        rescue StandardError => ex
          # Fail-closed: redact URLs on error to prevent leaking sensitive data
          OT.ld "[sentry] URL scrubbing failed: #{ex.class} - #{ex.message}"
          event.request.url = '[SCRUBBING_FAILED]' if event.request&.url
          if event.contexts.is_a?(Hash) && event.contexts['request'].is_a?(Hash)
            event.contexts['request']['url'] = '[SCRUBBING_FAILED]'
          end
          event
        end

        # Scrub sensitive path segments and query parameters from a URL
        #
        # Identifier paths (use MIN_IDENTIFIER_LENGTH discriminant):
        # - /secret/:identifier, /receipt/:identifier - v0.24 (62 chars) or v0.23 (31 chars)
        # - /private/:identifier, /metadata/:identifier - legacy aliases
        # - /incoming/:identifier - incoming secret submissions
        #
        # Auth token paths (variable length, scrub any segment):
        # - /forgot/:key, /auth/reset-password/:key, /account/email/confirm/:token
        # - /l/:shortcode - short links (variable length)
        #
        # Admin paths:
        # - /colonel/* - admin paths need full debugging context; scrub multi-segment
        #
        # @param url [String, nil] The URL to scrub
        # @return [String, nil] The scrubbed URL or original if nil/malformed
        def scrub_url(url)
          return url if url.nil? || url.empty?

          scrubbed = scrub_sensitive_paths(url)
          scrub_sensitive_query_params(scrubbed)
        rescue StandardError
          # Fail-closed: return redacted placeholder to prevent leaking sensitive data
          '[SCRUBBING_FAILED]'
        end

        # Pattern for identifier paths - matches segments >= MIN_IDENTIFIER_LENGTH chars
        # that look like base-36 identifiers (lowercase alphanumeric).
        # This avoids false positives on named paths like /receipt/recent.
        IDENTIFIER_PATH_PATTERN = %r{
          (/(?:secret|receipt|private|metadata|incoming)/)([0-9a-z]{#{MIN_IDENTIFIER_LENGTH},})
        }x

        # Pattern for auth token and shortcode paths - these have variable-length
        # tokens that should always be scrubbed regardless of length.
        AUTH_TOKEN_PATH_PATTERN = %r{
          (/(?:forgot|l)/)[^/?#]+                    |  # Password reset, shortcodes
          (/auth/reset-password/)[^/?#]+            |  # Auth reset password
          (/account/email/confirm/)[^/?#]+             # Email confirmation token
        }x

        # Pattern for colonel admin paths - multi-segment scrubbing
        COLONEL_PATH_PATTERN = %r{(/colonel/)[^/?#]+(?:/[^/?#]+)*}x

        # Query parameter names that contain sensitive data
        SENSITIVE_QUERY_PARAMS = %w[key secret token passphrase].freeze

        private

        def scrub_sensitive_paths(url)
          result = url

          # Scrub identifier paths (only if segment looks like an identifier)
          result = result.gsub(IDENTIFIER_PATH_PATTERN) do
            prefix = ::Regexp.last_match(1)
            "#{prefix}[REDACTED]"
          end

          # Scrub auth token paths (always scrub regardless of length)
          result = result.gsub(AUTH_TOKEN_PATH_PATTERN) do
            prefix = ::Regexp.last_match(1) ||
                     ::Regexp.last_match(2) ||
                     ::Regexp.last_match(3)
            "#{prefix}[REDACTED]"
          end

          # Scrub colonel admin paths
          result = result.gsub(COLONEL_PATH_PATTERN) do
            prefix = ::Regexp.last_match(1)
            "#{prefix}[REDACTED]"
          end

          result
        end

        def scrub_sensitive_query_params(url)
          return url unless url.include?('?')

          uri_part, query_string = url.split('?', 2)
          return url if query_string.nil? || query_string.empty?

          # Handle fragment if present
          query_part, fragment = query_string.split('#', 2)

          scrubbed_params = query_part.split('&', -1).map do |param|
            key, _value = param.split('=', 2)
            if key && SENSITIVE_QUERY_PARAMS.include?(key.downcase)
              "#{key}=[REDACTED]"
            else
              param
            end
          end

          result   = "#{uri_part}?#{scrubbed_params.join('&')}"
          result  += "##{fragment}" if fragment
          result
        end
      end
    end
  end
end
