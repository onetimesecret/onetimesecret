# lib/onetime/middleware/session_skip.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    ##
    # SessionSkip
    #
    # Suppresses session persistence for anonymous, unauthenticated probe
    # endpoints (#3997).
    #
    # {Onetime::Session} is a `Rack::Session::Abstract::PersistedSecure`
    # subclass, so every request that merely *loads* the session commits it —
    # writing a `session:<64-hex>` key to Valkey with the full 24h TTL and
    # returning a `Set-Cookie`. Health and status probes are polled constantly
    # by load balancers, uptime monitors and orchestrators, none of which keep
    # cookies, so each poll minted a fresh session that no one would ever use:
    # unbounded key growth for zero benefit.
    #
    # Setting `options[:skip]` is rack-session's own lever for this.
    # `commit_session?` (rack-session 2.1.2, abstract/id.rb:350) short-circuits
    # on it BEFORE any dirty check, so both the datastore write and the
    # `Set-Cookie` are suppressed regardless of what downstream middleware or
    # the app did to the session. That matters because the decisive dirtier is
    # not the app at all: {Onetime::Middleware::CsrfResponseHeader} calls
    # `AuthenticityToken.token(session)` (which does `session[:csrf] ||= …`) on
    # every response.
    #
    # ## Mounting
    #
    # Must be mounted AFTER {Onetime::Session}: `prepare_session` installs
    # `env['rack.session.options']` before calling the downstream app, so
    # anything below the session middleware can mutate that hash and the
    # session middleware will read the mutation on the way back out. Same
    # mechanism `apps/web/core/controllers/authentication.rb` uses to request
    # `[:renew]`.
    #
    # ## Path matching: exact, and mount-relative aware
    #
    # The universal middleware stack runs INSIDE `Rack::URLMap`, i.e. once per
    # mounted app, so `PATH_INFO` here is mount-relative: the v2 status route
    # arrives as `SCRIPT_NAME='/api/v2'` + `PATH_INFO='/status'`, while core
    # routes arrive as `SCRIPT_NAME=''` + `PATH_INFO='/health'`. Rejoining the
    # two is what lets a single flat list of external paths be configured.
    #
    # Matching is exact string equality — never prefix, substring or regex.
    # `/api/v*/secret/:identifier/status` is a capability-token data read
    # audited via SecretActivity; a prefix or substring match would sweep those
    # in and silently stop persisting sessions for real API traffic.
    #
    class SessionSkip
      # Rack env key holding the per-request session options hash that
      # rack-session's `commit_session?` consults.
      SESSION_OPTIONS_KEY = 'rack.session.options'

      # @param app [#call] downstream Rack app
      # @param skip_paths [Array<String>] full external paths (SCRIPT_NAME +
      #   PATH_INFO) for which session persistence is suppressed
      def initialize(app, skip_paths: [])
        @app        = app
        # Frozen at boot: the list is read on every request and never varies
        # per-request. nil-tolerant so a config gap degrades to "skip nothing"
        # (the pre-#3997 behaviour) rather than raising at boot.
        @skip_paths = Array(skip_paths).map { |path| path.to_s.freeze }.freeze
      end

      def call(env)
        if skip?(env)
          # Absent only if this middleware is mounted without a session
          # middleware above it. Nothing to suppress in that case.
          options        = env[SESSION_OPTIONS_KEY]
          options[:skip] = true if options
        end

        @app.call(env)
      end

      private

      # Full external path, reassembled from the URLMap mount prefix and the
      # mount-relative remainder. Compared with `==` only — see the class doc.
      def skip?(env)
        return false if @skip_paths.empty?

        path = "#{env['SCRIPT_NAME']}#{env['PATH_INFO']}"
        @skip_paths.include?(path)
      end
    end
  end
end
