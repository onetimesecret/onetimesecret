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
      Onetime::MissingSecret       => 404,
      Onetime::RecordNotFound      => 404,
      Onetime::FormError           => 422,
      Onetime::LimitExceeded       => 429,
      Onetime::EntitlementRequired => 403,
      Onetime::GuestRoutesDisabled => 403,
      Onetime::Forbidden           => 403,
      Onetime::Unauthorized        => 401,
    }.freeze

    DEFAULT_STATUS     = 500
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
    # @return [Hash] ADR-013 body hash
    def self.body_for(exception)
      return generic_body unless known_typed?(exception)

      # Typed Onetime::Problem and Onetime::Forbidden subclasses define a
      # purpose-built #to_h that returns the ADR-013 shape with any
      # class-specific fields (field, retry_after, entitlement, etc.).
      return exception.to_h if exception.respond_to?(:to_h) &&
                               (exception.is_a?(Onetime::Problem) ||
                                exception.is_a?(Onetime::Forbidden))

      # Onetime::Unauthorized is a marker class with no #to_h. The message
      # is caller-supplied and not sensitive at the auth boundary (e.g.
      # 'Invalid credentials').
      { error: exception.message, error_type: short_class_name(exception) }
    end

    def self.ancestor_status(exception)
      STATUS_BY_CLASS.each_pair do |klass, status|
        return status if exception.is_a?(klass)
      end
      nil
    end
    private_class_method :ancestor_status

    # An exception is "typed" iff it is an instance (or subclass) of a class
    # in STATUS_BY_CLASS. Tying the typed-check to the same source of truth
    # as the status mapping prevents drift.
    def self.known_typed?(exception)
      STATUS_BY_CLASS.each_key.any? { |klass| exception.is_a?(klass) }
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
