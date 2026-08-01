# lib/onetime/application/error_correlation.rb
#
# frozen_string_literal: true

module Onetime
  module Application
    # Correlates a JSON error response with the request log via the request_id.
    #
    # ## Why this exists
    #
    # Otto mints its own per-error id (Otto::Core::ErrorHandler, SecureRandom.hex),
    # but that id is a poor support handle: it is only added to the response body
    # in development, and it is logged on the separate 'Otto' logger whose context
    # carries no request_id. So in production an API consumer's error payload holds
    # no id that appears in our request log, and even in development there is no
    # single log line linking the error to the request_id.
    #
    # The request_id (env['HTTP_X_REQUEST_ID'], set by Rack::RequestId and returned
    # in the x-request-id response header) is logged by RequestLogger for every
    # request. Echoing it into the error body gives consumers one correlation id we
    # can grep straight out of the request log. We also stash the error_type into
    # env (ENV_ERROR_TYPE) so RequestLogger — sharing this same env hash one frame
    # up the middleware stack — records *what* failed next to the status, keyed to
    # that same id.
    #
    # ## Why it lives in its own module
    #
    # Like ErrorResolver, this lives outside OttoHooks so it is unit-testable in
    # isolation and so every typed-error edge can call the one implementation:
    # the Otto apps via OttoHooks#with_error_correlation, and the Roda /auth
    # surface via its Roda :error_handler (apps/web/auth/router.rb, through
    # Auth::ErrorTranslator.translate). Keeping a single implementation is what
    # makes "request_id in the body + error_type on the log line" a guarantee
    # across both routing stacks rather than two hand-synced copies.
    #
    # The module is dependency-free on purpose (no Onetime::* references): it
    # operates only on the body Hash, the Rack env Hash, and any Exception, so
    # both the lib-side Otto hooks and the app-side Roda router can require it
    # without dragging in either stack.
    module ErrorCorrelation
      # Rack env key under which the error classification is stashed for
      # RequestLogger to read. Single definition of this cross-module contract:
      # this module is the only production writer, RequestLogger the only reader.
      ENV_ERROR_TYPE = 'otto.error_type'

      # Rack env key carrying the request id, set upstream by Rack::RequestId
      # (MiddlewareStack) and mirrored in the x-request-id response header.
      ENV_REQUEST_ID = 'HTTP_X_REQUEST_ID'

      # Rack env key under which a throttle's retry-after delay (seconds) is
      # stashed for {Onetime::Middleware::RetryAfterHeader} to turn into the
      # `Retry-After` response header. Same cross-frame pattern as
      # ENV_ERROR_TYPE: neither routing stack can set a response header from
      # where it builds the error body (Otto's registered error handlers return
      # a body Hash and nothing else — Otto::Core::ErrorHandler owns the header
      # hash), so the value is handed to the middleware frame above instead.
      #
      # Read from the body rather than from the exception so ONE assignment
      # covers every limiter: `Onetime::LimitExceeded#to_h` already carries
      # `retry_after`, and every security limiter
      # (Reset/Login/Incoming/InviteToken/Passphrase/Feedback/Dns) raises that
      # one class. Bodies without the key stash nothing.
      ENV_RETRY_AFTER = 'otto.retry_after'

      module_function

      # Echo the request_id into the error body and stash the error_type (and,
      # for throttles, the retry-after delay) into env.
      #
      # Nil-safe on env: the Otto error-handler unit specs invoke the handler
      # blocks with no request, and any pre-middleware caller has no env — with
      # nothing to correlate against, the body is returned untouched.
      #
      # error_type prefers the body's own class-specific value, falling back to
      # the short exception class name so the request log still names failures
      # whose #to_h compacted error_type away (e.g. a FormError raised without
      # one). The body is never changed by that fallback — it only feeds the log.
      #
      # @param body [Hash] the JSON error body the handler is about to return
      # @param env [Hash, nil] the current request's Rack env
      # @param exception [Exception, nil] fallback source of error_type
      # @return [Hash] the body, with :request_id merged in when env carries one
      def apply(body, env, exception = nil)
        return body unless env

        error_type          = body[:error_type]
        error_type        ||= short_class_name(exception) if exception
        env[ENV_ERROR_TYPE] = error_type if error_type

        retry_after           = retry_after_seconds(body[:retry_after])
        env[ENV_RETRY_AFTER]  = retry_after if retry_after

        request_id = env[ENV_REQUEST_ID]
        request_id ? body.merge(request_id: request_id) : body
      end

      # Coerce a body's retry_after into a non-negative Integer of seconds, or
      # nil when it is absent/unusable. `Retry-After` is delay-seconds per RFC
      # 9110 §10.2.3, so a nil, negative, or non-numeric value must produce no
      # header rather than a malformed one.
      #
      # @param value [Object]
      # @return [Integer, nil]
      def retry_after_seconds(value)
        return nil unless value.is_a?(Numeric)

        seconds = value.to_i
        seconds.negative? ? nil : seconds
      end

      # @param exception [Exception]
      # @return [String, nil] the exception's class name without its namespace,
      #   or nil for an anonymous class (Class#name is nil → '' → split.last is
      #   nil). apply's `env[...] = error_type if error_type` guard drops that
      #   nil, so no bare/anonymous error_type is ever stashed.
      def short_class_name(exception)
        exception.class.name.to_s.split('::').last
      end
    end
  end
end
