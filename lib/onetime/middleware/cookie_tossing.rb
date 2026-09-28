# lib/onetime/middleware/cookie_tossing.rb
#
# frozen_string_literal: true

require 'rack/protection'

module Onetime
  module Middleware
    # Rack::Protection::CookieTossing bound to the application's session cookie
    # and given per-request state (#4466, RISK-2026-08-14-COOKIE-TOSSING).
    #
    # What the gem does (rack-protection 4.2.1, cookie_tossing.rb): `accepts?`
    # parses the raw Cookie header with `Rack::Utils.parse_query(header, ';,')`
    # and refuses the request when the session cookie NAME appears more than
    # once, or appears percent-encoded (`Rack::Utils.unescape(k) ==
    # session_key`). The reaction is `deny`: a 403 with a text/plain
    # "Forbidden" body, and the response carries a Set-Cookie clearing the
    # offending name for every prefix of the request path, with the request
    # host as the cookie domain. The downstream app never runs. A request with
    # one session cookie passes through unchanged.
    #
    # Two things the stock class needs from us:
    #
    # 1. The cookie name. The gem's `session_key` option shares its name with
    #    Base's env-key option and defaults to 'rack.session', but here it
    #    means the COOKIE name. Ours is `site.session.key`, the value
    #    MiddlewareStack hands Onetime::Session, so it is read from the same
    #    accessor (Onetime.session_config) and the two cannot disagree.
    #
    # 2. Per-request state. The gem memoizes `bad_cookies` on the middleware
    #    instance (`@bad_cookies ||= []`) and never clears it, and `accepts?`
    #    answers `bad_cookies.empty?`. Rack builds one instance per app, so
    #    after the first refused request every later request through that
    #    process would be refused too, whatever its cookies: one request with
    #    two session cookies would take the process down until restart. The
    #    list is not thread-safe under Puma either. Each request therefore
    #    runs on a copy of the instance that starts with an empty list.
    #
    # Where it runs: inside Onetime::Middleware::Security, which the universal
    # stack mounts below Onetime::Session (lib/onetime/application/
    # middleware_stack.rb). The session middleware has therefore already
    # parsed the Cookie header (Rack keeps the first value of a repeated name)
    # and, because IdentityResolution reads the session on the way down, has
    # loaded that first cookie's session before this refuses the request. The
    # refusal does not depend on it: the 403 is returned whichever cookie came
    # first, the store never adopts a cookie value that names no blob
    # (Onetime::Session#find_session), and the commit on the way back out
    # writes the loaded session back unchanged.
    class CookieTossing < Rack::Protection::CookieTossing
      # The cookie name when Onetime.session_config cannot be asked (a
      # standalone unit context). Same literal as Onetime::Session's default
      # and boot.rb's SESSION_DEFAULTS.
      DEFAULT_SESSION_KEY = 'onetime.session'

      # The gem's own #call, kept reachable under another name so the
      # per-request copy can run it.
      alias_method :call_once, :call
      protected :call_once

      def initialize(app, options = {})
        options = options.dup
        options[:session_key] ||= configured_session_key
        super(app, options)
      end

      def call(env)
        per_request = dup
        per_request.instance_variable_set(:@bad_cookies, [])
        per_request.call_once(env)
      end

      private

      def configured_session_key
        key = Onetime.session_config['key'] if Onetime.respond_to?(:session_config)
        key.to_s.empty? ? DEFAULT_SESSION_KEY : key
      rescue StandardError
        DEFAULT_SESSION_KEY
      end
    end
  end
end
