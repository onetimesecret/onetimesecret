# lib/onetime/session/active_session_gate.rb
#
# frozen_string_literal: true

module Onetime
  # Per-request enforcement of Rodauth's active-session table in full auth
  # mode.
  #
  # ## The gap this closes
  #
  # In full mode a signed-in browser holds two records: the Redis session blob
  # (`authenticated`, `external_id`, ...) that every per-request gate reads,
  # and a row in Rodauth's `account_active_session_keys` that only the
  # `/auth/active-sessions` routes ever consulted. Deleting that row — a user
  # revoking another device, or an operator revoking the session from Rodauth
  # Admin — therefore ended nothing: the blob kept answering `authenticated`
  # until it expired on its own. This module makes the row load-bearing: a
  # session whose row is gone is refused on its next request, by both the
  # Otto auth strategies and the controller-side SessionHelpers.
  #
  # ## The join
  #
  # Rodauth persists only HMAC(active_session_id) in the table, and
  # `Auth::Config::Features::ActiveSessions` stamps that same digest into the
  # app session as `active_session_id_hmac` at every login path. The lookup is
  # the table's primary key `(account_id, session_id)`, so it is one indexed
  # SELECT per authenticated request, memoized in the Rack env so the strategy
  # and the helpers never both pay for it.
  #
  # ## What is deliberately NOT enforced
  #
  # - **Sessions without the stamp.** A blob that carries no
  #   `active_session_id_hmac` (signed in before the stamp existed, or with the
  #   active_sessions feature off) cannot be joined and is left alone rather
  #   than mass-logged-out on deploy. Enforcement starts at its next login.
  # - **An unreachable authdb.** The check FAILS OPEN with an error log: a
  #   database blip must not sign out every full-mode user at once, and logins
  #   already fail during one. Revocation is delayed by the outage, not lost —
  #   the row is still gone when the database returns.
  # - **Inactivity / lifetime deadlines.** Rodauth applies those on the
  #   sessions page. This module only touches `last_use`, throttled to once per
  #   {TOUCH_INTERVAL}, so that page's inactivity sweep sees real activity
  #   instead of the login timestamp — now that the sweep's deletions actually
  #   end sessions, a stale `last_use` would sign out an active user.
  module ActiveSessionGate
    extend self

    # Per-request memo of the verdict, keyed in the Rack env.
    ENV_KEY = 'onetime.active_session_gate'

    # Minimum seconds between `last_use` writes for one session.
    TOUCH_INTERVAL = 300

    TABLE = :account_active_session_keys

    # True when the session's Rodauth active-session row has been removed.
    # Every other outcome — not full mode, no stamp to join on, row present,
    # authdb unreachable — is false.
    #
    # @param session [Hash, #[], nil] the Rack session (string keys)
    # @param env [Hash, nil] the Rack env, for the per-request memo
    # @return [Boolean]
    def revoked?(session, env: nil)
      verdict(session, env: env) == :revoked
    end

    # The full verdict, for callers and tests that need to tell the
    # non-revoked outcomes apart.
    #
    # @return [Symbol] :revoked, :active, :skipped, or :unavailable
    def verdict(session, env: nil)
      return env[ENV_KEY] if env.is_a?(Hash) && env.key?(ENV_KEY)

      result       = compute(session)
      env[ENV_KEY] = result if env.is_a?(Hash)
      result
    end

    private

    def compute(session)
      return :skipped unless applicable?(session)

      db = ::Auth::Database.connection
      return unavailable('no auth database connection') if db.nil?

      account_id = session['account_id']
      hmac       = session['active_session_id_hmac']

      row = db[TABLE].where(account_id: account_id, session_id: hmac).select(:last_use).first
      return :revoked if row.nil?

      touch(db, account_id, hmac, row[:last_use])
      :active
    rescue StandardError => ex
      unavailable("#{ex.class}: #{ex.message}")
    end

    # Full mode with the feature on, a session carrying both halves of the
    # join key, and the authdb constant loaded (it is only defined when the
    # auth application booted).
    def applicable?(session)
      return false unless session.respond_to?(:[])
      return false unless Onetime.auth_config.full_enabled? && Onetime.auth_config.active_sessions_enabled?
      return false if session['account_id'].to_s.empty? || session['active_session_id_hmac'].to_s.empty?

      defined?(::Auth::Database) ? true : false
    end

    # Best-effort, throttled `last_use` refresh. Its own rescue: a failed
    # write must not turn a verified-active session into an outage verdict.
    def touch(db, account_id, hmac, last_use)
      now = Time.now
      return if last_use && (now - last_use) < TOUCH_INTERVAL

      db[TABLE].where(account_id: account_id, session_id: hmac).update(last_use: now)
    rescue StandardError => ex
      OT.ld "[active_session_gate] last_use touch failed: #{ex.class}: #{ex.message}"
    end

    def unavailable(reason)
      OT.le "[active_session_gate] authdb unavailable, session not verified (fail open): #{reason}"
      :unavailable
    end
  end
end
