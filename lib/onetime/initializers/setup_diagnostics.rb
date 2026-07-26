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
            # This covers event.request.url, event.transaction (set from raw
            # PATH_INFO by Sentry::Rack::CaptureExceptions), and custom context
            # set via scope.set_context('request', ...) in error middleware.
            Onetime::Initializers::SetupDiagnostics.scrub_event_urls(event)

            # Scrub emails, identifiers, and sensitive paths interpolated into
            # exception messages and capture_message strings. Mirrors the
            # frontend's scrubEventMessages in enableDiagnostics.ts.
            Onetime::Initializers::SetupDiagnostics.scrub_event_messages(event)

            # Return the event if it passes validation
            event
          end

          # before_send does NOT run for transaction (performance) events —
          # with traces_sample_rate 0.1, sampled requests to /secret/:id would
          # otherwise ship raw paths in the transaction name, request URL, and
          # span data. Scrub them with the same rules as error events.
          config.before_send_transaction = ->(event, _hint) do
            return nil if event.nil?

            Onetime::Initializers::SetupDiagnostics.scrub_transaction_event(event)
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

          # Header names carrying full URLs that must be scrubbed like request.url.
          # sentry-ruby formats Rack's HTTP_REFERER into the capitalized "Referer"
          # (see Sentry::RequestInterface#filter_and_format_headers). We also match
          # the lowercase 'referer' defensively in case a caller populates headers
          # directly.
          URL_BEARING_HEADERS = %w[Referer referer].freeze

          # Scrub sensitive data from URLs in Sentry events
          #
          # Handles four URL locations:
          # 1. event.request.url - Standard Sentry request data
          # 2. event.contexts['request']['url'] - Custom context set by error middleware
          # 3. event.transaction - Set from raw PATH_INFO by Sentry::Rack::CaptureExceptions
          # 4. event.request.headers['Referer'] - Referer carries the previous URL,
          #    which can embed a secret identifier (e.g. /secret/<id>)
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

            # Scrub transaction name. The Rack middleware names transactions
            # from PATH_INFO (source :url), so an error on /secret/<key>
            # carries the identifier here unless scrubbed. Mirrors the
            # frontend, which scrubs event.transaction in beforeSend.
            if event.respond_to?(:transaction) && event.transaction
              original_txn = event.transaction
              scrubbed_txn = scrub_url(original_txn)
              if scrubbed_txn != original_txn
                event.transaction = scrubbed_txn
                OT.ld '[sentry] Scrubbed transaction'
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

            # Scrub URL-bearing request headers (Referer). The Referer carries
            # the previous page URL, which on OTS can embed a secret identifier
            # (e.g. https://host/secret/<id>). Scrub it through the same path
            # scrubber used for request.url.
            scrub_url_bearing_headers(event.request&.headers)

            event
          rescue StandardError => ex
            # Fail-closed: redact URLs on error to prevent leaking sensitive data
            # Note: intentionally not logging ex.message as it may contain URL fragments
            OT.ld "[sentry] URL scrubbing failed: #{ex.class}"
            event.request.url = '[SCRUBBING_FAILED]' if event.request&.url
            if event.respond_to?(:transaction) && event.transaction
              event.transaction = '[SCRUBBING_FAILED]'
            end
            if event.contexts.is_a?(Hash) &&
               event.contexts['request'].is_a?(Hash) &&
               event.contexts['request']['url']
              event.contexts['request']['url'] = '[SCRUBBING_FAILED]'
            end
            redact_url_bearing_headers(event.request&.headers)
            event
          end

          # Scrub URL-bearing request headers (e.g. Referer) in place through
          # the path scrubber. No-op unless headers is a Hash.
          #
          # @param headers [Hash, nil] event.request.headers
          # @return [void]
          def scrub_url_bearing_headers(headers)
            return unless headers.is_a?(Hash)

            URL_BEARING_HEADERS.each do |header_name|
              next unless headers[header_name].is_a?(String)

              original_hdr = headers[header_name]
              scrubbed_hdr = scrub_url(original_hdr)
              next if scrubbed_hdr == original_hdr

              headers[header_name] = scrubbed_hdr
              OT.ld "[sentry] Scrubbed request.headers['#{header_name}']"
            end
          end

          # Fail-closed redaction for URL-bearing request headers. No-op unless
          # headers is a Hash.
          #
          # @param headers [Hash, nil] event.request.headers
          # @return [void]
          def redact_url_bearing_headers(headers)
            return unless headers.is_a?(Hash)

            URL_BEARING_HEADERS.each do |header_name|
              next unless headers[header_name].is_a?(String)

              headers[header_name] = '[SCRUBBING_FAILED]'
            end
          end

          # Scrub sensitive data from transaction (performance) events
          #
          # Runs from before_send_transaction, which sentry-ruby invokes
          # instead of before_send for transaction events. Applies the same
          # URL rules as error events, plus span-level scrubbing: spans on a
          # TransactionEvent are already serialized to hashes, and http spans
          # carry request URLs in :description and data.
          #
          # Fail-closed: returns nil (drops the event) if span scrubbing
          # raises — losing one sampled transaction is cheaper than shipping
          # an unscrubbed URL.
          #
          # @param event [Sentry::TransactionEvent] The transaction event
          # @return [Sentry::TransactionEvent, nil] The scrubbed event, or nil
          def scrub_transaction_event(event)
            # Shared handling: request.url, transaction name, request context
            scrub_event_urls(event)

            # Span shape per sentry-ruby 6.5 Span#to_h: symbol keys, with
            # data using string-keyed OpenTelemetry conventions — URL lives
            # in data['url'], query string separately in data['http.query'].
            spans = event.respond_to?(:spans) ? event.spans : nil
            if spans.is_a?(Array)
              spans.each do |span|
                next unless span.is_a?(Hash)

                # Descriptions are free text ("GET https://host/secret/<id>")
                if span[:description].is_a?(String)
                  span[:description] = scrub_text(span[:description])
                end

                data = span[:data]
                next unless data.is_a?(Hash)

                data['url'] = scrub_url(data['url']) if data['url'].is_a?(String)
                if data['http.query'].is_a?(String)
                  data['http.query'] = scrub_query_string(data['http.query'])
                end
              end
            end

            event
          rescue StandardError => ex
            OT.ld "[sentry] Transaction scrubbing failed: #{ex.class}"
            nil
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
          # Free-text nets (issue #3794 C2/C4): after the path and named-param
          # passes, the email and verifiable-identifier nets sweep values that
          # ride under non-sensitive positions — e.g. ?ref=<62-char-id> or
          # ?email=user@example.com in a Referer or span URL. Named-param
          # redaction runs first so '[REDACTED]' placeholders are never
          # re-processed by the nets. This makes scrub_url the single
          # "thorough" tier for every URL-shaped value (request.url, Referer,
          # transaction name, span data['url'], span data['http.query']).
          #
          # @param url [String, nil] The URL to scrub
          # @return [String, nil] The scrubbed URL or original if nil/malformed
          def scrub_url(url)
            return url if url.nil? || url.empty?

            scrubbed = scrub_sensitive_paths(url)
            scrubbed = scrub_sensitive_query_params(scrubbed)
            scrubbed = scrubbed.gsub(EMAIL_PATTERN, '[EMAIL_REDACTED]')
            scrubbed.gsub(IDENTIFIER_TEXT_PATTERN, '[REDACTED]')
          rescue StandardError
            # Fail-closed: return redacted placeholder to prevent leaking sensitive data
            '[SCRUBBING_FAILED]'
          end

          # Scrub sensitive data from free text (exception messages,
          # capture_message strings, span descriptions).
          #
          # Since scrub_url now carries the email and identifier nets itself
          # (issue #3794), this is a semantic alias: both tiers apply the same
          # passes (paths, named params, emails, exact-length identifiers),
          # all gsub-based and safe on arbitrary text. Mirrors
          # scrubSensitiveStrings in src/plugins/core/diagnostics/scrubbers.ts.
          #
          # @param text [String, nil] The text to scrub
          # @return [String, nil] The scrubbed text
          def scrub_text(text)
            return text if text.nil? || text.empty?

            scrub_url(text)
          rescue StandardError
            '[SCRUBBING_FAILED]'
          end

          # Scrub sensitive parameters from a bare query string, as found in
          # span data['http.query']. Tolerates a leading '?' (issue #3794 —
          # the frontend had the same bug as its C1): without stripping it,
          # the first param would parse as key "?token" and dodge the
          # named-param redaction. Any leading '?' is preserved in the output.
          #
          # @param query [String] e.g. "key=abc123&ttl=3600"
          # @return [String] e.g. "key=[REDACTED]&ttl=3600"
          def scrub_query_string(query)
            return query if query.nil? || query.empty?

            # Prepend a fresh '?' so scrub_url parses the input as a query
            # string and applies its full pass stack (named params, emails,
            # identifier net), then strip it back off; the caller's original
            # prefix (if any) is restored below.
            bare     = query.delete_prefix('?')
            scrubbed = scrub_url("?#{bare}").delete_prefix('?')
            query.start_with?('?') ? "?#{scrubbed}" : scrubbed
          end

          # Scrub emails, identifiers, and sensitive paths from exception
          # messages and standalone messages.
          #
          # sentry-ruby 6.5: ErrorEvent#exception is an ExceptionInterface
          # whose #values are SingleExceptionInterface instances with an
          # attr_accessor :value holding the message string. Event#message
          # holds capture_message strings.
          #
          # @param event [Sentry::Event] The event to scrub
          # @return [Sentry::Event] The scrubbed event
          def scrub_event_messages(event)
            exception = event.respond_to?(:exception) ? event.exception : nil
            if exception.respond_to?(:values)
              Array(exception.values).each do |single|
                next unless single.respond_to?(:value) && single.value.is_a?(String)

                single.value = scrub_text(single.value)
              end
            end

            if event.respond_to?(:message) && event.message.is_a?(String) && !event.message.empty?
              event.message = scrub_text(event.message)
            end

            event
          rescue StandardError => ex
            # Fail-closed: redact the message and exception values rather than
            # shipping potentially-sensitive content unscrubbed. Mirrors the
            # fail-closed behavior of scrub_event_urls/scrub_text.
            # NOTE: intentionally not logging ex.message as it may contain the
            # very content we failed to scrub.
            OT.ld "[sentry] Message scrubbing failed: #{ex.class}"
            exception = event.respond_to?(:exception) ? event.exception : nil
            if exception.respond_to?(:values)
              Array(exception.values).each do |single|
                next unless single.respond_to?(:value) && single.value.is_a?(String)

                single.value = '[SCRUBBING_FAILED]'
              end
            end
            if event.respond_to?(:message) && event.message.is_a?(String) && !event.message.empty?
              event.message = '[SCRUBBING_FAILED]'
            end
            event
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

          # Email addresses in free text (exception messages, breadcrumbs).
          # Mirrors EMAIL_PATTERN in src/plugins/core/diagnostics/scrubbers.ts.
          EMAIL_PATTERN = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/

          # Verifiable identifiers in free text. 62 = v0.24 identifiers,
          # 31 = legacy v0.23.
          #
          # The 62-char branch is UNANCHORED so a secret glued to adjacent
          # word characters (`?ref=<id>abc`, `<id>x`, `load <id>_meta`) is
          # still caught. A \b-anchored 62 branch silently leaked all of
          # those shapes. The over-redaction risk is minimal: no ops-useful
          # token is >= 62 chars, and partially redacting a longer blob is
          # fail-safe, not a bug. The 31-char branch stays \b-anchored and
          # length-exact so ops-useful values of nearby lengths — trace IDs
          # (32 hex), commit hashes (40 hex) — survive untouched.
          #
          # Mirrors VERIFIABLE_ID_PATTERN in
          # src/plugins/core/diagnostics/scrubbers.ts, with ONE intentional
          # divergence: the backend pattern is case-SENSITIVE ([0-9a-z]
          # only), because the backend controls its own identifier
          # generation (lowercase base-36). The frontend is
          # case-insensitive. Do NOT "fix" this asymmetry by making the two
          # patterns identical — the difference is by design.
          IDENTIFIER_TEXT_PATTERN = /(?:[0-9a-z]{62}|\b[0-9a-z]{31}\b)/

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
