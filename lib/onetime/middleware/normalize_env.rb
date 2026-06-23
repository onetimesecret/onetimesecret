# lib/onetime/middleware/normalize_env.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # NormalizeEnv
    #
    # Restores Rack-spec compliance to the request env after upstream
    # middleware redacts sensitive request headers.
    #
    # Otto's IPPrivacyMiddleware clears privacy-sensitive request headers
    # (HTTP_REFERER, HTTP_USER_AGENT) by assigning the anonymized value even
    # when that value is nil — its own comment is "Always replace, even if
    # nil, to clear original sensitive data":
    #
    #     env['HTTP_REFERER']    = fingerprint.referer       # nil when absent
    #     env['HTTP_USER_AGENT'] = fingerprint.anonymized_ua # nil when absent
    #
    # The Rack SPEC requires every CGI-style env key (one without a period)
    # to have a String value. A nil value is silently harmless in production
    # — readers treat a missing key and a nil-valued key identically — but it
    # violates the spec, and Rack::Lint (enabled in development by
    # Core::Middleware::ViteProxy) rejects the whole request with:
    #
    #     Rack::Lint::LintError: env variable HTTP_REFERER has non-string value nil
    #
    # Deleting a nil-valued CGI key is the spec-compliant equivalent of the
    # clear the upstream middleware intended, and keeps Rack::Lint useful for
    # catching genuine middleware bugs. This must run immediately after
    # IPPrivacyMiddleware so the rest of the stack sees a compliant env.
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
