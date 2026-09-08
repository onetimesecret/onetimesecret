# lib/onetime/session/active_session_gate.rb
#
# frozen_string_literal: true

module Onetime
  # Per-request enforcement of Rodauth's active-session table in full auth
  # mode.
  #
  # ## Terms
  #
  # In full mode a signed-in browser is backed by two records in two stores,
  # and this module is the only place that reads both. The names below are
  # used throughout the gate, its callers and its specs, and are recorded in
  # docs/architecture/terminology.md under "Session Terminology".
  #
  # - **Rack session**: the per-request HTTP session at `env['rack.session']`,
  #   bound to the `onetime.session` cookie and stored by {Onetime::Session}
  #   as an encrypted blob at `session:<sid>` in Redis. It carries
  #   `authenticated`, `external_id`, `account_id` and the join key. Every
  #   per-request gate reads it; so does Rodauth.
  # - **active-session row**: a row in Rodauth's `account_active_session_keys`
  #   table in the authdb, primary key `(account_id, session_id)`, written by
  #   Rodauth's active_sessions feature at login. The account's sessions page,
  #   "sign out everywhere", Rodauth's inactivity/lifetime sweep and Rodauth
  #   Admin operate on these rows and on nothing else.
  # - **join key**: `active_session_id_hmac`, the HMAC of Rodauth's
  #   active_session_id, stamped into the Rack session at every login path by
  #   apps/web/auth/config/features/active_sessions.rb. It equals the row's
  #   `session_id` column, the only form Rodauth persists.
  # - **revoke**: remove an active-session row. **destroy**: delete a Rack
  #   session's blob from Redis, which is what logout does. **refuse**: answer
  #   a request 401 (strategies) or `authenticated? == false` (helpers) while
  #   leaving the Rack session in Redis. Refusing is all this gate ever does.
  #
  # ## The gap this closes
  #
  # Before this gate only the `/auth/active-sessions` routes consulted the
  # active-session row. Revoking it therefore ended nothing: the Rack session
  # kept answering `authenticated` until it expired on its own. The gate makes
  # the row load-bearing: a Rack session whose row is gone is refused on its
  # next request, by both the Otto auth strategies and the controller-side
  # SessionHelpers.
  #
  # ## The join
  #
  # One indexed SELECT on the table's primary key per authenticated request,
  # `(session['account_id'], session['active_session_id_hmac'])`, memoized in
  # the Rack env so the strategy and the helpers never both pay for it.
  #
  # ## Failure posture: closed
  #
  # A Rack session whose active-session row cannot be checked is refused. The
  # row is the revocation authority in full mode, so an unreachable authdb
  # means the question "is this Rack session still valid" has no answer, and
  # an unanswered question is not a yes. Logins already need the same
  # database, so the site is degraded either way; what failing closed adds is
  # that a revoked Rack session never outlives the outage. The verdict stays
  # distinguishable (:unavailable, not :revoked) so the refusal is logged and
  # reported as an outage, not as a revocation, and the Rack session is left
  # in Redis to be honoured again when the database returns.
  #
  # ## What is deliberately NOT enforced
  #
  # - **Rack sessions without a join key.** One signed in before the stamp
  #   existed, or with the active_sessions feature off, cannot be joined to a
  #   row and is left alone rather than mass-logged-out on deploy. Enforcement
  #   starts at its next login.
  # - **Inactivity / lifetime deadlines.** Rodauth applies those on the
  #   sessions page. This module only touches the row's `last_use`, throttled
  #   to once per {TOUCH_INTERVAL}, so that page's inactivity sweep sees real
  #   activity instead of the login timestamp — now that the sweep's
  #   revocations actually end Rack sessions, a stale `last_use` would sign
  #   out an active user.
  module ActiveSessionGate
    extend self

    # Per-request memo of the verdict, keyed in the Rack env.
    ENV_KEY = 'onetime.active_session_gate'

    # Minimum seconds between `last_use` writes for one active-session row.
    TOUCH_INTERVAL = 300

    TABLE = :account_active_session_keys

    # Verdicts on which the Rack session must be refused: its active-session
    # row is gone, or the authdb that would say so cannot be reached (fail
    # closed).
    REFUSED = [:revoked, :unavailable].freeze

    # True when the Rack session must be refused: its active-session row has
    # been revoked, or could not be checked. False when the row is present or
    # the gate does not apply (not full mode, no join key).
    #
    # @param session [Hash, #[], nil] the Rack session (string keys)
    # @param env [Hash, nil] the Rack env, for the per-request memo
    # @return [Boolean]
    def revoked?(session, env: nil)
      REFUSED.include?(verdict(session, env: env))
    end

    # The full verdict, for callers and tests that need to tell the
    # non-revoked outcomes apart.
    #
    # @return [Symbol] :active (row present), :revoked (row gone),
    #   :unavailable (authdb could not answer), or :skipped (gate does not
    #   apply)
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

    # Full mode with the feature on, a Rack session carrying both halves of
    # the join key, and the authdb constant loaded (it is only defined when
    # the auth application booted).
    def applicable?(session)
      return false unless session.respond_to?(:[])
      return false unless Onetime.auth_config.full_enabled? && Onetime.auth_config.active_sessions_enabled?
      return false if session['account_id'].to_s.empty? || session['active_session_id_hmac'].to_s.empty?

      defined?(::Auth::Database) ? true : false
    end

    # Best-effort, throttled `last_use` refresh on the active-session row. Its
    # own rescue: a failed write must not turn a verified-active verdict into
    # an outage verdict.
    def touch(db, account_id, hmac, last_use)
      now = Time.now
      return if last_use && (now - last_use) < TOUCH_INTERVAL

      db[TABLE].where(account_id: account_id, session_id: hmac).update(last_use: now)
    rescue StandardError => ex
      OT.ld "[active_session_gate] last_use touch on active-session row failed: #{ex.class}: #{ex.message}"
    end

    def unavailable(reason)
      OT.le "[active_session_gate] authdb unreachable, active-session row unchecked, Rack session refused (fail closed): #{reason}"
      :unavailable
    end
  end
end
