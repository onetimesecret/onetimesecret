# lib/onetime/middleware/session_skip.rb
#
# frozen_string_literal: true

require 'rack/constants'
require 'otto/utils'

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
    # `Set-Cookie` are suppressed no matter which layer dirtied the session —
    # and several do, before the app is ever involved:
    # `Rack::Protection::AuthenticityToken#accepts?` runs
    # `session[:csrf] ||= …` on every request ahead of its safe-method check,
    # and {Onetime::Middleware::CsrfResponseHeader} mints the same key when
    # exposing the masked token. Only :skip stops the write; suppressing any
    # one dirtier would not.
    #
    # Caveat: `commit_session` consults `options[:drop]`/`options[:renew]`
    # BEFORE :skip (abstract/id.rb:381) and deletes the stored session for
    # them. A path that is both in skip_paths and reaches a drop/renew call
    # site (logout in authentication.rb, password rotation in account.rb)
    # would delete the live session and skip writing its replacement — a
    # silent logout. None of the shipped probe paths route anywhere near
    # those call sites; keep it that way when editing the list.
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
    # ## Path matching: normalized, exact, and mount-relative aware
    #
    # The universal middleware stack runs INSIDE `Rack::URLMap`, i.e. once per
    # mounted app, so `PATH_INFO` here is mount-relative: the v2 status route
    # arrives as `SCRIPT_NAME='/api/v2'` + `PATH_INFO='/status'`, while core
    # routes arrive as `SCRIPT_NAME=''` + `PATH_INFO='/health'`. Rejoining the
    # two is what lets a single flat list of external paths be configured.
    #
    # The joined path is canonicalized with `Otto::Utils.normalize_path` — the
    # same normalization the Otto router applies before dispatch. The router
    # serves `/api/v2/status/` and percent-encoded spellings like
    # `/api/v2/%73tatus` as the status route, so matching the raw string would
    # let those aliases reach the handler while dodging the skip — reopening
    # the per-probe session mint for any client that appends a slash.
    #
    # After normalization, matching is exact string equality — never prefix,
    # substring or regex. `/api/v*/secret/:identifier/status` is a
    # capability-token data read audited via SecretActivity; a prefix or
    # substring match would sweep those in and silently stop persisting
    # sessions for real API traffic.
    #
    class SessionSkip
      # @param app [#call] downstream Rack app
      # @param skip_paths [Array<String>] full external paths (SCRIPT_NAME +
      #   PATH_INFO) for which session persistence is suppressed
      def initialize(app, skip_paths: [])
        @app        = app
        # Frozen at boot: the list is read on every request and never varies
        # per-request. nil-tolerant so a config gap degrades to "skip nothing"
        # (the pre-#3997 behaviour) rather than raising at boot. Entries are
        # normalized the same way skip? normalizes the request path, so a
        # configured `/health/` still matches.
        @skip_paths = Array(skip_paths).map { |path| Otto::Utils.normalize_path(path.to_s).freeze }.freeze
      end

      def call(env)
        if skip?(env)
          # Absent only if this middleware is mounted without a session
          # middleware above it. Nothing to suppress in that case.
          options        = env[Rack::RACK_SESSION_OPTIONS]
          options[:skip] = true if options
        end

        @app.call(env)
      end

      private

      # Full external path — the URLMap mount prefix plus the mount-relative
      # remainder — canonicalized the way the Otto router canonicalizes before
      # dispatch. Compared with `==` only — see the class doc.
      def skip?(env)
        return false if @skip_paths.empty?

        path = Otto::Utils.normalize_path("#{env['SCRIPT_NAME']}#{env['PATH_INFO']}")
        @skip_paths.include?(path)
      end
    end
  end
end
