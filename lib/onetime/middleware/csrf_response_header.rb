# lib/onetime/middleware/csrf_response_header.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    ##
    # CsrfResponseHeader
    #
    # Adds a masked CSRF token to response headers for frontend consumption.
    #
    # Rack::Protection::AuthenticityToken handles validation and stores
    # a raw token in session[:csrf]. Rather than exposing that raw token
    # directly (which would be vulnerable to BREACH attacks on compressed
    # HTTPS responses), this middleware uses AuthenticityToken.token() to
    # return a per-request masked version. The masked token is XOR'd with
    # a one-time pad, so the header value changes on every response while
    # still validating against the same underlying session token.
    #
    # Usage:
    #   use Rack::Protection::AuthenticityToken  # validates requests
    #   use Onetime::Middleware::CsrfResponseHeader  # exposes masked token
    #
    class CsrfResponseHeader
      # State-changing methods that Rack::Protection::AuthenticityToken
      # validates. Safe methods (GET/HEAD/OPTIONS) are never CSRF-checked, so
      # they must not pay the session-load cost below nor emit rejection logs.
      UNSAFE_METHODS = %w[POST PUT PATCH DELETE].freeze

      # Session key holding the raw CSRF token. This is AuthenticityToken's
      # default `key: :csrf` (security.rb does not override it). SessionHash
      # normalizes the symbol to its stored string key, so reading session[:csrf]
      # mirrors exactly what AuthenticityToken reads — and the read is pure
      # (set_token only runs inside AuthenticityToken during @app.call).
      CSRF_SESSION_KEY = :csrf

      def initialize(app)
        @app = app
      end

      def call(env)
        # #3837 (root cause of #3831): a CSRF 403 has two very different causes.
        # AuthenticityToken#accepts? calls set_token (session[:csrf] ||= random)
        # BEFORE validating, so after @app.call the token is ALWAYS present and
        # the two cases are indistinguishable. The only moment we can tell them
        # apart is here, before @app.call. Unsafe methods only — reading the
        # session lazy-loads it, a cost safe requests must not incur.
        request_method = env['REQUEST_METHOD']
        unsafe         = UNSAFE_METHODS.include?(request_method)
        had_csrf       = unsafe && csrf_token_present?(env['rack.session'])

        status, headers, body = @app.call(env)

        session = env['rack.session']
        if session
          csrf_token              = Rack::Protection::AuthenticityToken.token(session)
          headers['X-CSRF-Token'] = csrf_token if csrf_token
        end

        log_csrf_rejection(env, had_csrf) if unsafe && status == 403

        [status, headers, body]
      end

      private

      # True when the session already carries a non-empty raw CSRF token.
      # Reads with AuthenticityToken's own key; the read forces a lazy session
      # load, which is why the caller gates this on unsafe methods.
      def csrf_token_present?(session)
        return false unless session

        token = session[CSRF_SESSION_KEY]
        !token.nil? && !token.to_s.empty?
      end

      # Observability only (#3837): classify a CSRF 403. Never logs token
      # values or secrets — only method + path context. This logs the CSRF
      # REJECTION and is distinct from the Part 2 cookie-drop warning.
      def log_csrf_rejection(env, had_csrf)
        context = { method: env['REQUEST_METHOD'], path: env['PATH_INFO'] }

        if had_csrf
          # The session held a token but the submitted one did not match: a
          # genuine forged/stale request — real CSRF rejection.
          OT.lw '[CsrfResponseHeader] CSRF 403 token-mismatch: session had a CSRF token; submitted token invalid or absent', **context
        else
          # No token in the session when the request arrived: the session was
          # lost or never persisted between issuing the token and this request.
          # This is the session-continuity break behind #3837/#3831, not forgery.
          OT.lw '[CsrfResponseHeader] CSRF 403 session-continuity break: no CSRF token in session at request start; session lost or not persisted', **context
        end
      end
    end
  end
end
