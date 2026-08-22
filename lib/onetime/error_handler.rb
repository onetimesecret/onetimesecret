# lib/onetime/error_handler.rb
#
# frozen_string_literal: true

# lib/onetime/error_handler.rb
#
# Provides robust error handling for non-critical operations, particularly
# side-effects in authentication hooks. Errors are logged with context but
# don't interrupt the parent operation.
#
require_relative 'utils/diagnostics_ref'

module Onetime
  module ErrorHandler
    extend Onetime::LoggerMethods

    # Rodauth may not be loaded in all contexts (e.g., CLI tools, unit tests).
    # Resolve the error class once at load time; fall back to a never-raised
    # placeholder so the rescue clause is syntactically valid but never matches.
    RODAUTH_INTERNAL_ERROR = if defined?(::Rodauth::InternalRequestError)
                               ::Rodauth::InternalRequestError
                             else
                               Class.new(Exception) # rubocop:disable Lint/InheritException
                             end

    # Executes a block and logs any errors without re-raising.
    # Useful for side-effects that shouldn't break critical operations.
    #
    # @param operation [String] Name of the operation for logging/tracking
    # @param context [Hash] Additional context to log (e.g., account_id: 123)
    # @yield Block to execute with error protection
    #
    # @example
    #   ErrorHandler.safe_execute('create_customer', account_id: 123) do
    #     Customer.create!(email: 'user@example.com')
    #   end
    #
    def self.safe_execute(operation, **context)
      yield
    rescue RODAUTH_INTERNAL_ERROR => ex
      # Rodauth internal errors are expected to be handled by the caller's flow,
      # but we still log them before re-raising to ensure visibility.
      log_error(operation, ex, context.merge(rodauth_internal: true))
      raise ex
    rescue StandardError => ex
      log_error(operation, ex, context)
      track_error(operation) if trackable?

      sentry_ok = sentry_available?
      app_logger.debug '[sentry] error_handler → capture decision',
        {
          operation: operation,
          exception_class: ex.class.name,
          sentry_defined: defined?(Sentry) ? true : false,
          sentry_initialized: (defined?(Sentry) && Sentry.initialized?) || false,
          sentry_available: sentry_ok,
        }
      if sentry_ok
        capture_error(operation, ex, context)
      else
        app_logger.debug '[sentry] error_handler skipped — sentry_available=false',
          {
            operation: operation,
          }
      end
      nil
    end

    # Rack env keys for headers that carry authentication credentials or
    # session state. These are redacted from Sentry capture-decision debug
    # logs because that logging runs exactly when operators enable debug
    # mode in production to diagnose dropped events — the same conditions
    # under which a leaked Basic Auth header would reach the log aggregator.
    SENSITIVE_HEADER_KEYS = %w[
      HTTP_AUTHORIZATION
      HTTP_PROXY_AUTHORIZATION
      HTTP_COOKIE
      HTTP_X_API_KEY
      HTTP_X_AUTH_TOKEN
    ].freeze

    # Filters a Rack env hash down to HTTP_* request headers suitable for
    # debug logging, with sensitive headers replaced by "[FILTERED]". The
    # `rescue false` guards against non-String keys — Rack's spec says keys
    # are Strings, but this debug path must never raise.
    #
    # @param env [Hash] Rack request env
    # @return [Hash] subset of env whose keys start with "HTTP_", with
    #   sensitive values redacted
    def self.http_headers_from(env)
      return {} unless env.respond_to?(:select)

      headers = env.select { |k, _v| k.is_a?(String) && k.start_with?('HTTP_') }
      headers.each_with_object({}) do |(k, v), result|
        result[k] = SENSITIVE_HEADER_KEYS.include?(k) ? '[FILTERED]' : v
      end
    end

    # Opt-in allowlist of request field names (params or header names) that
    # may be attached to an error log line or error-tracking event (Sentry
    # scope context, RequestLogger's :debug capture mode, etc).
    #
    # This is the one dial that governs how much request data "unhandled
    # exception" reporting is allowed to show, across every capture_error /
    # capture_exception call site in the app plus RequestLogger's :debug
    # capture. It is empty by default: with no entries configured,
    # #safe_request_context below returns only path/method/ip, so an error
    # response is logged with exactly the same request-derived fields as any
    # successful request — mirroring Django's SafeExceptionReporterFilter
    # stance of hiding request data unless a view (here: an operator)
    # explicitly opts specific field names in.
    #
    # Configure via the top-level `http.allowed_error_fields` key in
    # etc/defaults/logging.defaults.yaml (loaded into Onetime.logging_conf —
    # a sibling of OT.conf, not nested inside it) or the
    # LOG_HTTP_ALLOWED_ERROR_FIELDS comma-separated env override. Never add
    # names like password/secret/token/passphrase.
    #
    # @return [Array<String>] allow-listed field names, empty by default
    def self.allowed_error_fields
      Array(Onetime.logging_conf&.dig('http', 'allowed_error_fields'))
    rescue StandardError
      []
    end

    # Builds the request-derived context safe to attach to an error log line
    # or error-tracking event. The query string is never included — only the
    # bare path — and request parameters are included only when their name
    # is explicitly allow-listed via #allowed_error_fields. This is what
    # keeps a POST body's secret/passphrase value (or a query-string secret
    # smuggled onto any request) from ever reaching an error report: there
    # is no blocklist to keep up to date, just an empty allowlist by default.
    #
    # @param req [Rack::Request, Otto::Request, nil] the current request
    # @return [Hash] safe subset with :path/:method/:ip, plus :params only
    #   when the allowlist is non-empty and something on the request matches
    def self.safe_request_context(req)
      return {} unless req

      context = {
        path: (req.path if req.respond_to?(:path)),
        method: (req.request_method if req.respond_to?(:request_method)),
        ip: (req.ip if req.respond_to?(:ip)),
      }.compact

      allowed = allowed_error_fields
      return context if allowed.empty? || !req.respond_to?(:params)

      filtered         = req.params.each_with_object({}) do |(k, v), result|
        next unless allowed.include?(k.to_s)

        result[k] = loggable_scalar?(v) ? v : v.to_s
      end
      context[:params] = filtered unless filtered.empty?
      context
    rescue StandardError
      {}
    end

    # Builds the Sentry `user` hash for whoever this event is about.
    #
    # Sentry counts "users affected" off event.user.id and nothing else, so
    # every backend event we send without one is an issue that reads as zero
    # affected users no matter how many accounts it actually hit. That is the
    # gap this closes: an operator needs to tell "one account is broken" from
    # "every account is broken", which is the same question the frontend's
    # diagnostics_ref answers for browser events.
    #
    # The id is ALWAYS a DiagnosticsRef — an opaque, keyed, one-way digest.
    # Never the email, never the custid/extid, never the session id, never the
    # IP. Those are the identifiers this whole boundary exists to keep out of
    # the diagnostics backend, and Sentry's user object is not an exemption
    # from it; feeding one in here would also make it a searchable field.
    #
    # Returns nil rather than a partial hash in every declining case:
    #
    #   - anonymous (no candidate, blank email, or #anonymous? is true) — an
    #     anonymous request has no user to report, and a placeholder id would
    #     silently merge every anonymous visitor into one "affected user".
    #   - unconfigured — DiagnosticsRef declines when no keying secret is
    #     usable, which is the default in dev and test. No user is strictly
    #     better than an unkeyed one.
    #   - any raised error — derivation must never be the reason an exception
    #     goes unreported, so this swallows and returns nil. Losing the
    #     attribution is survivable; losing the event is not.
    #
    # A nil return means the caller sets NO user at all. It must not fall back
    # to some other identifier, and it must not set `{ id: nil }` — Sentry
    # treats a nil id as a distinct anonymous-ish user rather than as absence.
    #
    # @param candidate [#email, #anonymous?, String, nil] customer or email
    # @return [Hash{Symbol=>String}, nil] { id: <16 hex> }, or nil
    def self.diagnostics_actor(candidate)
      return nil if candidate.nil?
      return nil if candidate.respond_to?(:anonymous?) && candidate.anonymous?

      email = candidate.respond_to?(:email) ? candidate.email : candidate
      return nil if email.nil? || email.to_s.strip.empty?

      ref = Onetime::Utils::DiagnosticsRef.actor_ref(email)
      return nil if ref.nil? || ref.to_s.empty?

      { id: ref }
    rescue StandardError
      # Deliberately silent and deliberately broad: see above. There is no
      # logger call here either, because the failure modes that would reach
      # this rescue take the email with them into the log line.
      nil
    end

    # Sets the pseudonymous user on a Sentry scope, if one can be derived.
    #
    # Pass an EVENT-SCOPED scope — the block form of Sentry.capture_exception,
    # or one from Sentry.with_scope. Setting a user on the ambient current
    # scope would outlive the request that established it and mis-attribute
    # every later event on the same thread.
    #
    # @param scope [Sentry::Scope] event-scoped Sentry scope
    # @param candidate [#email, #anonymous?, String, nil] customer or email
    # @return [Boolean] true when a user was set
    def self.set_diagnostics_actor(scope, candidate)
      return false unless scope.respond_to?(:set_user)

      user = diagnostics_actor(candidate)
      return false if user.nil?

      scope.set_user(user)
      true
    rescue StandardError
      false
    end

    # Lua script for atomic INCR + EXPIRE (prevents race condition
    # where a crash between the two commands leaves a permanent key).
    TRACK_ERROR_LUA = <<~LUA
      local c = redis.call('INCR', KEYS[1])
      if tonumber(c) == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
      return c
    LUA

    # TTL for error tracking keys: 7 days in seconds
    ERROR_TRACKING_TTL = 86_400 * 7

    class << self
      private

      # Logs error details with operation context
      def log_error(operation, ex, context)
        app_logger.error "error-handler: #{operation} failed",
          {
            exception: ex,
            operation: operation,
            **context,
          }
      end

      # Tracks error frequency in Redis for monitoring
      # Keeps daily counters for 7 days to identify patterns
      # Uses atomic Lua script to prevent race conditions between INCR and EXPIRE.
      def track_error(operation)
        return unless Familia.dbclient

        key = "errors:rodauth:#{operation}:#{Date.today.strftime('%Y%m%d')}"
        Familia.dbclient.eval(TRACK_ERROR_LUA, keys: [key], argv: [ERROR_TRACKING_TTL])
      rescue StandardError => ex
        # Don't let tracking errors break the error handler itself
        app_logger.error 'error-handler: Failed to track error',
          {
            exception: ex,
            operation: 'track_error',
          }
      end

      # Captures error in Sentry with context
      def capture_error(operation, ex, context)
        # An `email:`/`cust:` entry is CONSUMED, not forwarded: it becomes the
        # pseudonymous Sentry user and is removed from the context hash. Every
        # caller today passes account_id/customer_id instead, so this is
        # mostly a guard — but the alternative is that the first caller to add
        # one ships a raw email into an error_handler context.
        subject = context[:email] || context[:cust] || context[:customer]
        context = context.except(:email, :cust, :customer)

        event_id = Sentry.capture_exception(ex) do |scope|
          # Event-scoped: capture_exception's block scope is per-event, so
          # this cannot bleed onto a later event on the same thread.
          Onetime::ErrorHandler.set_diagnostics_actor(scope, subject)
          scope.set_context('error_handler', { operation: operation, **context })
          scope.set_level(:warning)
          scope.set_tags(operation: operation, error_handler: true)
        end
        app_logger.debug '[sentry] error_handler capture_error returned',
          {
            operation: operation,
            event_id: event_id,
            exception_class: ex.class.name,
          }
      rescue StandardError => ex
        # Don't let Sentry errors break the error handler itself
        app_logger.error 'error-handler: Failed to capture in Sentry',
          {
            exception: ex,
            operation: 'capture_error',
          }
      end

      # Check if error tracking is available
      def trackable?
        !Familia.dbclient.nil?
      end

      # Check if Sentry is configured
      def sentry_available?
        defined?(Sentry) && Sentry.initialized?
      end

      # True for value types safe to attach to a log line or Sentry context
      # as-is; anything else (Array, Hash, custom object) is coerced to a
      # String by the caller instead of risking a non-JSON-safe value.
      def loggable_scalar?(v)
        v.is_a?(String) || v.is_a?(Numeric) || v == true || v == false || v.nil?
      end
    end
  end
end
