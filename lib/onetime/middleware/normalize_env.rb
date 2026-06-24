# lib/onetime/middleware/normalize_env.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # NormalizeEnv
    #
    # Completes the upstream privacy redaction by dropping request-header keys
    # the privacy middleware scrubbed to nil. This does NOT restore any value
    # — by the time it runs, the original headers are already gone.
    #
    # Otto's IPPrivacyMiddleware redacts privacy-sensitive request headers
    # (HTTP_REFERER, HTTP_USER_AGENT) by *overwriting* them in place with the
    # anonymized value, even when that value is nil — its own comment is
    # "Always replace, even if nil, to clear original sensitive data":
    #
    #     env['HTTP_REFERER']    = fingerprint.referer       # nil when absent
    #     env['HTTP_USER_AGENT'] = fingerprint.anonymized_ua # nil when absent
    #
    # That leaves a present-but-nil key. Deleting it is strictly privacy-
    # preserving: to every downstream reader env['HTTP_REFERER'] is nil either
    # way, and an absent key is indistinguishable from a request that never
    # carried the header — whereas a nil-valued key can hint that one was
    # scrubbed. So this finishes the redaction; it never reverses it.
    #
    # The side benefit is Rack-spec compliance. The SPEC requires every
    # CGI-style env key (one without a period) to hold a String value. The
    # nil is harmless in production, but Rack::Lint (enabled in development by
    # Core::Middleware::ViteProxy) rejects the whole request with:
    #
    #     Rack::Lint::LintError: env variable HTTP_REFERER has non-string value nil
    #
    # Wire this immediately after IPPrivacyMiddleware so the rest of the stack
    # only ever sees fully-redacted, spec-compliant headers.
    class NormalizeEnv
      def initialize(app)
        @app = app
      end

      def call(env)
        env.delete_if { |key, value| value.nil? && cgi_key?(key) }
        @app.call(env)
      end

      private

      # CGI-style keys are those without a period. Rack reserves dotted keys
      # (rack.*, otto.*, identity.*) for arbitrary objects that may legitimately
      # be nil, so those are left untouched.
      def cgi_key?(key)
        key.is_a?(String) && !key.include?('.')
      end
    end
  end
end
