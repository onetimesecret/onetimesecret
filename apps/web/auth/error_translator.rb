# apps/web/auth/error_translator.rb
#
# frozen_string_literal: true

require 'onetime/errors'

module Auth
  # Translates typed Onetime exceptions into ADR-013 wire-shape responses
  # ({ error, error_type, ...class-specific fields }).
  #
  # The Auth app runs on Roda, not Otto. Otto-based apps register their typed
  # exception handlers via Onetime::Application::OttoHooks#configure_otto_request_hook;
  # Roda has no equivalent register-by-class mechanism, so this module fills
  # the same role for the Auth Router via Roda's :error_handler plugin
  # (see apps/web/auth/router.rb).
  #
  # The status-code mapping intentionally parallels otto_hooks.rb. If a typed
  # exception's status changes in one place, it should change here as well.
  # Coverage symmetry as of this commit: RecordNotFound, MissingSecret,
  # FormError, LimitExceeded, EntitlementRequired, GuestRoutesDisabled,
  # Forbidden, Unauthorized are registered in BOTH layers. A future refactor
  # may extract a shared registry consumed by both layers.
  #
  # This module is pure: input is an Exception, output is a [status, body_hash]
  # pair (and, from .log_entry, what the caller should log). It performs no
  # logging, no i18n resolution, and no IO. The caller is
  # responsible for any auth-layer logging and for request/log correlation
  # (apps/web/auth/router.rb runs the translated body through the shared
  # Onetime::Application::ErrorCorrelation, exactly as the Otto hooks do).
  module ErrorTranslator
    # HTTP status codes for typed Onetime exceptions. Lookup is exact-class
    # first, then ancestor walk for subclasses not directly registered.
    STATUS_BY_CLASS = {
      Onetime::MissingSecret => 404,
      Onetime::RecordNotFound => 404,
      Onetime::FormError => 422,
      Onetime::LimitExceeded => 429,
      Onetime::EntitlementRequired => 403,
      Onetime::GuestRoutesDisabled => 403,
      Onetime::Forbidden => 403,
      Onetime::Unauthorized => 401,
      Onetime::AccountProvisioningFailed => 409,
      # Provisioning persisted nothing and the next request retries it; 503,
      # never the 409 above (see Onetime::AccountProvisioningUnavailable).
      Onetime::AccountProvisioningUnavailable => 503,
      # An auth gate could not READ this host's policy (#4139/#4157). 503, not
      # the gate's usual 404: see Onetime::AuthPolicyUnavailable. Registered on
      # the FAMILY, not on SigninPolicyUnavailable alone — this table's lookup
      # walks ancestors, so the sign-up sibling gets the same status without a
      # second copy to keep in sync (otto_hooks cannot do that: Otto dispatches
      # on the exact class name and needs one handler per subclass).
      Onetime::AuthPolicyUnavailable => 503,
    }.freeze

    # Per-class log severity for translated exceptions. Mirrors the
    # `log_level:` values passed to `router.register_error_handler` in
    # `lib/onetime/application/otto_hooks.rb` so the Roda Auth app and Otto
    # apps emit at the same level for the same exception class. Exceptions
    # not present here fall back to DEFAULT_LOG_LEVEL (the unhandled-500
    # path; matches Otto's `structured_log(:error, 'Unhandled error …')`).
    LOG_LEVEL_BY_CLASS = {
      Onetime::MissingSecret => :info,
      Onetime::RecordNotFound => :info,
      Onetime::FormError => :info,
      Onetime::LimitExceeded => :warn,
      Onetime::EntitlementRequired => :info,
      Onetime::GuestRoutesDisabled => :info,
      Onetime::Forbidden => :warn,
      Onetime::Unauthorized => :warn,
      Onetime::AccountProvisioningFailed => :warn,
      Onetime::AccountProvisioningUnavailable => :warn,
      Onetime::AuthPolicyUnavailable => :error,
    }.freeze

    # The authdb could not take the request in time: a SQLite write lock held
    # longer than Auth::Database::SQLITE_BUSY_TIMEOUT_MS, or no pooled
    # connection free within Sequel's pool timeout. Both mean more queued
    # work than the server has capacity for, not a defect in the request, so
    # they answer 503 with a Retry-After (RFC 9110 15.6.4) instead of the
    # generic 500. Matched by predicate, not by STATUS_BY_CLASS: Sequel raises
    # the SQLite case as a plain Sequel::DatabaseError whose only distinguishing
    # mark is the driver exception it wraps.
    AUTHDB_BUSY_STATUS = 503
    AUTHDB_BUSY_BODY   = {
      error: 'The service is busy. Please try again shortly.',
      error_type: 'AuthDatabaseBusy',
      retry_after: 1,
    }.freeze

    DEFAULT_STATUS     = 500
    DEFAULT_LOG_LEVEL  = :error
    DEFAULT_ERROR_TYPE = 'ServerError'
    DEFAULT_MESSAGE    = 'Internal Server Error'

    # Log messages for the router's error handler (see .log_entry).
    TRANSLATED_LOG_MESSAGE = 'Auth router translated exception'
    UNHANDLED_LOG_MESSAGE  = 'Auth router unhandled exception'

    # ADR-013 body for router-level 404 fallbacks (status_handler(404) and
    # the route-block catch-all in apps/web/auth/router.rb). Single source of
    # truth so the two paths cannot drift; the integration spec pins it.
    NOT_FOUND_BODY = { error: 'Not Found', error_type: 'NotFound' }.freeze

    # Translate an exception into a [status, body_hash] pair per ADR-013.
    # body_hash is suitable for direct return from a Roda route body (the
    # :json plugin serializes hashes).
    #
    # @param exception [Exception]
    # @return [Array(Integer, Hash)]
    def self.translate(exception)
      [status_for(exception), body_for(exception)]
    end

    # @param exception [Exception]
    # @return [Integer] HTTP status code
    def self.status_for(exception)
      return AUTHDB_BUSY_STATUS if authdb_busy?(exception)

      STATUS_BY_CLASS[exception.class] || ancestor_status(exception) || DEFAULT_STATUS
    end

    # @param exception [Exception]
    # @return [Symbol] Log severity (:info, :warn, :error)
    def self.level_for(exception)
      return :warn if authdb_busy?(exception)

      LOG_LEVEL_BY_CLASS[exception.class] || ancestor_level(exception) || DEFAULT_LOG_LEVEL
    end

    # Whether this module answers the exception with something other than
    # the generic 500: a class registered in STATUS_BY_CLASS (or a subclass
    # of one), or a saturated authdb. Decided by what the exception IS, never
    # by the status: a deliberate 503 is translated, an unknown 500 is not.
    #
    # @param exception [Exception]
    # @return [Boolean]
    def self.translated?(exception)
      authdb_busy?(exception) || known_typed?(exception)
    end

    # What the router's error handler should log: a level, a message and a
    # payload. A translated exception logs at its own level (.level_for) under
    # TRANSLATED_LOG_MESSAGE, so a retryable 503 (AuthDatabaseBusy,
    # AccountProvisioningUnavailable) is a :warn and not an "unhandled
    # exception" at :error. Anything else is a genuine unhandled exception:
    # :error with the exception, so production failures are not silent.
    #
    # A translated 5xx keeps the exception in the payload: the client is told
    # only "busy" or "unavailable", and the message and backtrace (which
    # statement waited on the lock, which read failed) exist nowhere else.
    #
    # @param exception [Exception]
    # @return [Array(Symbol, String, Hash)] level, message, payload
    def self.log_entry(exception)
      unless translated?(exception)
        return [DEFAULT_LOG_LEVEL, UNHANDLED_LOG_MESSAGE, { exception: exception }]
      end

      status              = status_for(exception)
      payload             = {
        exception_class: exception.class.name,
        error_type: body_for(exception)[:error_type],
        status: status,
      }
      payload[:exception] = exception if status >= 500

      [level_for(exception), TRANSLATED_LOG_MESSAGE, payload]
    end

    # @param exception [Exception]
    # @return [Hash] ADR-013 body hash
    def self.body_for(exception)
      return AUTHDB_BUSY_BODY.dup if authdb_busy?(exception)
      return generic_body unless known_typed?(exception)

      # Typed Onetime exceptions in STATUS_BY_CLASS that define #to_h
      # (Onetime::Problem and Onetime::Forbidden subclasses) return their
      # purpose-built ADR-013 hash with class-specific fields (field,
      # retry_after, entitlement, etc.). Using respond_to? rather than
      # explicit is_a? checks avoids drift as new typed exceptions are
      # registered.
      return exception.to_h if exception.respond_to?(:to_h)

      # Onetime::Unauthorized is a marker class with no #to_h. The message
      # is caller-supplied and not sensitive at the auth boundary (e.g.
      # 'Invalid credentials').
      { error: exception.message, error_type: short_class_name(exception) }
    end

    # @param exception [Exception]
    # @return [Boolean] whether the authdb was saturated (see AUTHDB_BUSY_STATUS)
    def self.authdb_busy?(exception)
      return true if defined?(Sequel::PoolTimeout) && exception.is_a?(Sequel::PoolTimeout)
      return false unless defined?(SQLite3::BusyException)

      exception.respond_to?(:wrapped_exception) && exception.wrapped_exception.is_a?(SQLite3::BusyException)
    end

    # Walk the exception's actual inheritance chain (not STATUS_BY_CLASS
    # iteration order) so the lookup is robust to hash reordering and
    # returns the closest ancestor's status.
    def self.ancestor_status(exception)
      exception.class.ancestors.each do |ancestor|
        return STATUS_BY_CLASS[ancestor] if STATUS_BY_CLASS.key?(ancestor)
      end
      nil
    end
    private_class_method :ancestor_status

    def self.ancestor_level(exception)
      exception.class.ancestors.each do |ancestor|
        return LOG_LEVEL_BY_CLASS[ancestor] if LOG_LEVEL_BY_CLASS.key?(ancestor)
      end
      nil
    end
    private_class_method :ancestor_level

    # An exception is "typed" iff one of its ancestors is a key in
    # STATUS_BY_CLASS. Tying the typed-check to the same source of truth
    # as the status mapping prevents drift.
    def self.known_typed?(exception)
      exception.class.ancestors.any? { |ancestor| STATUS_BY_CLASS.key?(ancestor) }
    end
    private_class_method :known_typed?

    def self.generic_body
      { error: DEFAULT_MESSAGE, error_type: DEFAULT_ERROR_TYPE }
    end
    private_class_method :generic_body

    def self.short_class_name(exception)
      exception.class.name.to_s.split('::').last
    end
    private_class_method :short_class_name
  end
end
