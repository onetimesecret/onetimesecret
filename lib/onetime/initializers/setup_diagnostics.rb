# lib/onetime/initializers/setup_diagnostics.rb
#
# frozen_string_literal: true

require 'uri'

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

        # Select DSN based on execution mode:
        # - :worker/:scheduler use workers DSN (with backend fallback)
        # - :web/:cli use backend DSN
        dsn       = select_sentry_dsn
        site_host = OT.conf.dig('site', 'host')

        OT.ld "[init] Setting up Sentry (mode=#{OT.execution_mode})..."

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

        # Safely log first part of DSN for debugging, plus the host and
        # project id parsed out of the DSN path so multi-project setups
        # can tell which Sentry project each boot is targeting. Project
        # name isn't encoded in the DSN (Sentry only exposes the numeric
        # project id), so host + id is the most specific identifier
        # available without hitting the API.
        dsn_preview              = "#{dsn[0..10]}..."
        dsn_host, dsn_project_id = parse_sentry_dsn(dsn)
        OT.boot_logger.info(
          "[init] Sentry: Initializing project=#{dsn_project_id || 'unknown'} " \
          "host=#{dsn_host || 'unknown'} dsn=#{dsn_preview}",
        )

        # Only require Sentry if we have a DSN. We call explicitly
        # via Kernel to aid in testing.
        Kernel.require 'sentry-ruby'
        Kernel.require 'stackprof'

        Sentry.init do |config|
          config.dsn         = dsn
          config.environment = OT.env

          # Strict trace continuation (sentry-ruby 6.5+) — when an org_id is
          # configured, refuse to continue distributed traces whose
          # sentry-org_id baggage doesn't match. Defends against a third-party
          # service (instrumented by Sentry under a different org) injecting
          # trace context into our request path. org_id must be set explicitly
          # for self-hosted Sentry because DSN-based parsing only works for the
          # SaaS ingest hostnames. When org_id is blank, strict mode is left
          # off so inbound requests carrying any sentry-org_id baggage (e.g.
          # from a browser running sentry-javascript) still stitch into the
          # trace. The value is sourced from the `defaults` block of the
          # diagnostics.sentry config and propagated into each peer hash by
          # Onetime::Config#apply_defaults_to_peers; reading from `backend`
          # is correct for any execution mode because the same value lives
          # on every peer.
          sentry_org_id                    = OT.conf.dig('diagnostics', 'sentry', 'backend', 'org_id')
          config.org_id                    = sentry_org_id
          config.strict_trace_continuation = !sentry_org_id.to_s.strip.empty?

          # Determine Sentry release identifier. Priority:
          # 1. SENTRY_RELEASE env var (explicit override)
          # 2. .commit_hash.txt file (baked into Docker image by CI)
          # 3. OT::VERSION.details fallback (local development)
          # This ensures frontend and backend report the same release identifier.
          config.release = resolve_sentry_release

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

        # Add contextual tags for filtering without fragmenting environments.
        # site_host identifies the deployment; jurisdiction is optional.
        # Normalize jurisdiction to lowercase for consistent Sentry tag filtering
        # (tags are case-sensitive, so US vs us would create separate filters).
        # Service tag enables filtering by entry point (web vs worker).
        # Note: config.tags was removed in sentry-ruby 4.0+; use Sentry.set_tags instead.
        jurisdiction = OT.conf.dig('features', 'regions', 'current_jurisdiction').to_s.downcase
        tags         = {
          site_host: site_host,
          service: execution_mode_to_service,
          jurisdiction: jurisdiction.empty? ? nil : jurisdiction,
        }.compact
        Sentry.set_tags(tags)

        # Set runtime state
        Onetime::Runtime.update_infrastructure(d9s_enabled: true)
      end

      private

        # Parses a Sentry DSN to extract host and project id. A Sentry DSN
        # has the shape "https://PUBLIC_KEY@HOST/PROJECT_ID"; the project id
        # is the last path segment. Returns [host, project_id], either of
        # which may be nil if the DSN is malformed.
        def parse_sentry_dsn(dsn)
          uri        = URI.parse(dsn)
          project_id = uri.path.to_s.split('/').reject(&:empty?).last
          [uri.host, project_id]
        rescue URI::InvalidURIError
          [nil, nil]
        end

        # Selects the appropriate Sentry DSN based on execution mode.
        #
        # Workers and scheduler processes can report to a separate Sentry project
        # for better organization and alerting. Falls back to backend DSN if
        # workers DSN is not configured.
        #
        # @return [String, nil] The DSN to use, or nil if not configured
        def select_sentry_dsn
          sentry_config = OT.conf.dig('diagnostics', 'sentry')
          backend_dsn   = sentry_config.dig('backend', 'dsn')

          case OT.execution_mode
          when :worker, :scheduler
            workers_dsn         = sentry_config.dig('workers', 'dsn')
            workers_dsn_present = !workers_dsn.to_s.strip.empty?
            dsn                 = workers_dsn_present ? workers_dsn : backend_dsn
            if workers_dsn_present
              OT.ld "[init] Sentry: Using workers DSN for #{OT.execution_mode} mode"
            else
              OT.ld "[init] Sentry: Workers DSN not configured, using backend DSN for #{OT.execution_mode} mode"
            end
            dsn
          else
            backend_dsn
          end
        end

        # Resolves the Sentry release identifier with fallback chain:
        # 1. SENTRY_RELEASE env var (explicit override, e.g., production deploy)
        # 2. OT::VERSION.get_build_info (reads .commit_hash.txt or git, returns 'dev' fallback)
        #
        # @return [String] The release identifier for Sentry
        def resolve_sentry_release
          # Check env var first (allows explicit override)
          env_release = ENV.fetch('SENTRY_RELEASE', '').strip
          return env_release unless env_release.empty?

          # Delegate to VERSION which handles .commit_hash.txt and git fallback
          OT::VERSION.get_build_info
        end

        # Maps execution mode to Sentry service tag value.
        #
        # Service tags enable filtering events by entry point:
        # - 'web' for HTTP requests (Puma/Rack backend)
        # - 'worker' for background jobs (Sneakers workers, scheduler)
        #
        # Matches frontend convention where service is 'web' or 'api'.
        # @see src/plugins/core/enableDiagnostics.ts
        # @see https://github.com/onetimesecret/onetimesecret/issues/2964
        #
        # @return [String] The service tag value ('web' or 'worker')
        def execution_mode_to_service
          case OT.execution_mode
          when :worker, :scheduler
            'worker'
          else
            # :backend (Puma), :cli, or any other mode maps to 'web'
            'web'
          end
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
                OT.ld '[sentry] Scrubbed request.url'
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
                OT.ld '[sentry] Scrubbed contexts.request.url'
              end
            end

            event
          rescue StandardError => ex
            # Fail-closed: redact URLs on error to prevent leaking sensitive data
            # Note: intentionally not logging ex.message as it may contain URL fragments
            OT.ld "[sentry] URL scrubbing failed: #{ex.class}"
            event.request.url = '[SCRUBBING_FAILED]' if event.request&.url
            if event.contexts.is_a?(Hash) &&
               event.contexts['request'].is_a?(Hash) &&
               event.contexts['request']['url']
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
            result.gsub(COLONEL_PATH_PATTERN) do
              prefix = ::Regexp.last_match(1)
              "#{prefix}[REDACTED]"
            end
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
