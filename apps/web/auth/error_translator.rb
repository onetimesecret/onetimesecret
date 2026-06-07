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
  # pair. It performs no logging, no i18n resolution, and no IO. The caller is
  # responsible for any auth-layer logging.
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
    }.freeze

    DEFAULT_STATUS     = 500
    DEFAULT_LOG_LEVEL  = :error
    DEFAULT_ERROR_TYPE = 'ServerError'
    DEFAULT_MESSAGE    = 'Internal Server Error'

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
      STATUS_BY_CLASS[exception.class] || ancestor_status(exception) || DEFAULT_STATUS
    end

    # @param exception [Exception]
    # @return [Symbol] Log severity (:info, :warn, :error)
    def self.level_for(exception)
      LOG_LEVEL_BY_CLASS[exception.class] || ancestor_level(exception) || DEFAULT_LOG_LEVEL
    end

    # @param exception [Exception]
    # @return [Hash] ADR-013 body hash
    def self.body_for(exception)
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
