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
  # next request at all three places a full-mode request is authenticated:
  # the Otto auth strategies (BaseSessionAuthStrategy), the controller-side
  # SessionHelpers, and the Roda auth router ahead of every `/auth/*` route,
  # Rodauth's own included.
  #
  # ## The join
  #
  # One indexed SELECT on the table's primary key per authenticated request,
  # `(session['account_id'], session['active_session_id_hmac'])`, memoized in
  # the Rack env so the strategy and the helpers never both pay for it. The
  # same SELECT asks the database whether the row is past either deadline
  # and whether `last_use` is due a refresh (both below), so the steady state
  # stays read-only.
  #
  # ## Deadlines
  #
  # Rodauth's two session deadlines are enforced here, in the same SELECT:
  # a row whose `last_use` is older than {INACTIVITY_DEADLINE} or whose
  # `created_at` is older than {LIFETIME_DEADLINE} is removed, as Rodauth's
  # own sweep (`remove_inactive_sessions`) would remove it, and the Rack
  # session is refused as :revoked. They cannot live anywhere else: the gate
  # keeps `last_use` fresh on every request (below), so a deadline checked
  # only on the sessions page would find every row active, and Rodauth's
  # `check_active_session` has no call site on this surface. The two values
  # are owned by this module and fed to Rodauth's configuration from here
  # (apps/web/auth/config/features/active_sessions.rb), so the gate and the
  # sessions page's sweep can never disagree about when a row is dead.
  #
  # An expired row is refused before `last_use` is touched, so it is never
  # revived by the request that finds it.
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
  #   row and is left alone rather than mass-logged-out on deploy. This
  #   exemption covers only sessions that already exist: since the stamp
  #   became load-bearing, a login whose stamp fails is refused outright
  #   (apps/web/auth/config/features/active_sessions.rb), so no new Rack
  #   session can be minted without a join key. The unstamped population
  #   ages out within Rodauth's session_lifetime_deadline.
  #
  # ## The `last_use` refresh
  #
  # The row's `last_use` is what the inactivity deadline reads, so the gate
  # refreshes it, throttled to once per {TOUCH_INTERVAL}, and an active user
  # is never signed out for inactivity. The deadline decisions, the throttle
  # decision and the refreshed value are all computed by the database
  # against its own CURRENT_TIMESTAMP, the clock Rodauth wrote the columns
  # with. They are naive timestamps; comparing them with Ruby's Time.now
  # would silently break on any host whose process TZ differs from the
  # database session's, in one direction expiring live sessions and never
  # refreshing, in the other never expiring and refreshing on every request.
  module ActiveSessionGate
    extend self

    # Per-request memo of the verdict, keyed in the Rack env.
    ENV_KEY = 'onetime.active_session_gate'

    # Minimum seconds between `last_use` writes for one active-session row.
    TOUCH_INTERVAL = 300

    # Rodauth's session deadlines, in seconds. Owned here and fed to Rodauth
    # (`session_inactivity_deadline`, `session_lifetime_deadline`) so this
    # gate and the sessions page's sweep apply the same two values.
    INACTIVITY_DEADLINE = 86_400*3  # 72 hours since `last_use`
    LIFETIME_DEADLINE   = 2_592_000 # 30 days since `created_at`

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
      return unavailable(session, 'no auth database connection') if db.nil?

      row_ds = db[TABLE].where(
        account_id: session['account_id'],
        session_id: session['active_session_id_hmac'],
      )
      row    = row_ds.select(
        Sequel.as(past_expression(:last_use, INACTIVITY_DEADLINE), :inactive),
        Sequel.as(past_expression(:created_at, LIFETIME_DEADLINE), :outlived),
        Sequel.as(past_expression(:last_use, TOUCH_INTERVAL), :touch_due),
      ).first
      return revoked(session) if row.nil?
      return expire(row_ds, session, 'inactivity') if row[:inactive].to_i == 1
      return expire(row_ds, session, 'lifetime') if row[:outlived].to_i == 1

      touch(row_ds, session) if row[:touch_due].to_i == 1
      :active
    rescue StandardError => ex
      unavailable(session, "#{ex.class}: #{ex.message}")
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

    # `1` when the row's timestamp `column` (`last_use` and `created_at` are
    # both NOT NULL in the schema) is more than `seconds` old, else `0`.
    # Evaluated by the database against its own CURRENT_TIMESTAMP, never
    # against Ruby's clock, and as an integer CASE rather than a bare boolean
    # because SQLite returns booleans as integers and Sequel only typecasts
    # declared boolean columns. `Sequel.date_sub` comes from the
    # date_arithmetic extension, which Auth::Database loads on the authdb
    # connection (Rodauth's active_sessions feature needs it too).
    def past_expression(column, seconds)
      past = Sequel[column] < Sequel.date_sub(Sequel::CURRENT_TIMESTAMP, seconds: seconds)
      Sequel.case({ past => 1 }, 0)
    end

    # The row is past the named deadline: remove it, as Rodauth's sweep
    # would, and refuse the Rack session. Removal is best effort, with its
    # own rescue: the SELECT has already decided, and a row this delete
    # cannot reach is collected by the sessions page's sweep instead.
    # Logged at info because the user sees a sign-out with no action of
    # their own behind it, and support needs to be able to name the deadline.
    def expire(row_ds, session, deadline)
      OT.info "[active_session_gate] active-session row past its #{deadline} deadline; removed, Rack session refused #{who(session)}"
      row_ds.delete
      :revoked
    rescue StandardError => ex
      OT.lw '[active_session_gate] expired active-session row could not be removed; the sessions-page sweep ' \
            "will collect it #{who(session)}: #{ex.class}: #{ex.message}"
      :revoked
    end

    # The row is gone: revoked from the sessions page, by "sign out
    # everywhere", by an operator, or by the sweep. Every caller refuses on
    # this; the line here is the one place the refusal is tied to the row
    # rather than to a route, and it names the account for the operator who
    # just revoked it.
    def revoked(session)
      OT.info "[active_session_gate] no active-session row for the Rack session; refused #{who(session)}"
      :revoked
    end

    # The join, for log lines. The join key is a digest of a random token,
    # not a credential and not the Rack sid, and is what the sessions page,
    # "sign out everywhere" and Rodauth Admin key their rows on, so it is
    # what an operator can match a refusal against. Truncated all the same;
    # a prefix is enough to match on.
    def who(session)
      "(account_id=#{session['account_id']} join_key=#{session['active_session_id_hmac'].to_s[0, 12]}…)"
    end

    # Best-effort `last_use` refresh on the active-session row, in the
    # database's clock. Its own rescue: a failed write must not turn a
    # verified-active verdict into an outage verdict. Logged at warn, not
    # debug: the row's `last_use` is what Rodauth's inactivity sweep reads,
    # so a write that keeps failing ends in a live session being revoked a
    # day later, and that logout must be traceable to its cause.
    def touch(row_ds, session)
      row_ds.update(last_use: Sequel::CURRENT_TIMESTAMP)
    rescue StandardError => ex
      OT.lw '[active_session_gate] last_use refresh on active-session row failed; if this persists the ' \
            "inactivity deadline will end a live session #{who(session)}: #{ex.class}: #{ex.message}"
    end

    def unavailable(session, reason)
      OT.le '[active_session_gate] authdb unreachable, active-session row unchecked, Rack session refused ' \
            "(fail closed) #{who(session)}: #{reason}"
      :unavailable
    end
  end
end
