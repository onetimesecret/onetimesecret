# lib/onetime/middleware/api_cache_policy.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    ##
    # ApiCachePolicy
    #
    # Defaults every response served under `/api` to
    # `Cache-Control: private, no-store` (RISK-2026-09-19-03).
    #
    # The API answers with account data, session lists, receipts and secret
    # metadata, and until now sent no `Cache-Control` at all: outside the
    # colonel audit export no API route set one. Without validators a browser
    # rarely reuses such a response, but a shared intermediary is not bound by
    # browser heuristics, and OWASP ASVS 5.0.0 requirement 14.3.2 asks for an
    # explicit anti-caching header on sensitive responses. Web Core HTML,
    # `GET /bootstrap/me` and `/auth` already send this value (#4461).
    #
    # ## Every API response, not only authenticated ones
    #
    # The finding was filed against authenticated responses. The default is
    # wider on purpose: an anonymous API response can be just as sensitive (a
    # receipt or a secret's metadata fetched by a guest, addressed by a
    # capability in the URL), no API route is meant to be cached (none ever
    # set a policy that allows it), and a rule with no condition cannot be
    # wrong about who was authenticated. It is the same choice
    # Core::Middleware::RequestSetup makes for every HTML response.
    #
    # ## Never overwrites
    #
    # A route that sets its own `Cache-Control` keeps it, whatever it says
    # (the colonel audit export sends `no-store`). A future cacheable API
    # response opts out by setting its own header.
    #
    # ## Why a middleware, and why here
    #
    # The API is nine Otto applications with two base classes, and Otto builds
    # its error responses inside the gem. One mount in the universal
    # MiddlewareStack covers all of them, successes and refusals alike. The
    # stack runs INSIDE each Rack::URLMap mount, so the mount prefix is in
    # SCRIPT_NAME and the rest in PATH_INFO; the two are joined before they
    # are matched.
    #
    class ApiCachePolicy
      # Rack 3 requires lowercase response header names.
      HEADER = 'cache-control'
      POLICY = 'private, no-store'

      # `/api` itself or anything under it; never `/apiary` or `/api-docs`.
      API_PATH = %r{\A/api(?:/|\z)}

      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)

        headers[HEADER] = POLICY if headers && api_request?(env) && !header_present?(headers)

        [status, headers, body]
      end

      private

      def api_request?(env)
        "#{env['SCRIPT_NAME']}#{env['PATH_INFO']}".match?(API_PATH)
      end

      # Case-insensitive: Otto's error path builds a plain Hash with lowercase
      # keys, while a route may have written 'Cache-Control'.
      def header_present?(headers)
        headers.each_key.any? { |key| key.to_s.casecmp(HEADER).zero? }
      end
    end
  end
end
