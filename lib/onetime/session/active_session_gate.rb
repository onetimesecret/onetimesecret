# lib/onetime/session/active_session_gate.rb
#
# frozen_string_literal: true

require_relative '../session'
require_relative 'activity'
require_relative 'remember_me'

module Onetime
  # Enforces Rodauth active-session membership when enabled in full auth mode.
  # See docs/architecture/terminology.md (Session Terminology) for the two stores.
  #
  # The gate joins on `(account_id, active_session_id_hmac)` and memoizes one
  # lookup per request. Sessions missing either join field are skipped;
  # login must refuse if a required stamp fails. A missing or expired row refuses the
  # session as `:revoked` and forfeits remember-me. An authdb failure refuses
  # as `:unavailable` without destroying the Rack session.
  #
  # The gate and Rodauth's sweep share deadline rules. Use the database clock
  # for deadline checks and `last_use` updates: these timestamps have no time
  # zone. Check expiry before touching the row. Passive requests still verify
  # and expire rows but never refresh `last_use`.
  module Session::ActiveSessionGate
    extend self

    # Per-request memo of the verdict, keyed in the Rack env.
    ENV_KEY = 'onetime.active_session_gate'

    # `{ queries: Integer, writes: Integer }` issued against {TABLE} on this
    # request. Absent when the gate did not apply or never ran.
    STATS_ENV_KEY = 'onetime.active_session_gate.stats'

    # Minimum seconds between `last_use` writes for one active-session row.
    TOUCH_INTERVAL = 300

    # Rodauth's session deadlines, in seconds. Owned here and fed to Rodauth
    # (`session_inactivity_deadline`, `session_lifetime_deadline`) so this
    # gate and the sessions page's sweep apply the same two values. The
    # lifetime deadline is the operator's `site.session.absolute_timeout`
    # (SESSION_ABSOLUTE_TIMEOUT), read through {lifetime_deadline}; this is
    # its shipped default.
    INACTIVITY_DEADLINE       = 86_400*3  # 72 hours since `last_use`
    DEFAULT_LIFETIME_DEADLINE = 2_592_000 # 30 days since `created_at`

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

      result       = compute(session, env)
      env[ENV_KEY] = result if env.is_a?(Hash)
      result
    end

    # The session identity changed inside this request (login or logout): the
    # verdict for the previous identity may not outlive it. The counts stay;
    # they describe the request, not the session.
    def forget(env)
      return unless env.is_a?(Hash)

      env.delete(ENV_KEY)
    end

    # Logout: remove the active-session row this Rack session joins to, as
    # Rodauth's own logout does (`remove_current_session`). Call it BEFORE the
    # Rack session is cleared, while the join key is still readable.
    #
    # Clearing the Rack session is not enough. The store is last-writer-wins,
    # and every response re-sends the session cookie: a request that loaded
    # the session before the logout and commits after it writes the whole
    # blob back under the old id AND hands the browser the old cookie again.
    # Observed in a browser (dashboard fetches in flight during a logout in
    # another tab): the next GET /bootstrap/me answered `authenticated`. With
    # the row gone that resurrected blob is refused as revoked on its next
    # request, exactly like a session revoked from the sessions page.
    #
    # Never raises and never blocks the logout: a row this delete cannot
    # reach is still bounded by the inactivity deadline and the sweep.
    #
    # @return [Boolean] true when a row was removed
    def end_session(session, env: nil)
      return false unless applicable?(session)

      db = ::Auth::Database.connection
      return false if db.nil?

      removed = row_dataset(db, session).delete
      forget(env)
      removed.positive?
    rescue StandardError => ex
      OT.lw "[active_session_gate] active-session row could not be removed at logout #{who(session)}: " \
            "#{ex.class}: #{ex.message}"
      false
    end

    # The rows that are past a deadline, as one SQL condition: a row that is
    # not remembered and idle past {INACTIVITY_DEADLINE}, a remembered row
    # whose `remember_until` has passed, or any row older than
    # {lifetime_deadline}. The per-request SELECT below asks the same three
    # questions one at a time so the refusal can name the deadline; Rodauth's
    # sweep (`inactive_session_cond`, overridden in
    # apps/web/auth/config/features/active_sessions.rb) deletes on this.
    #
    # @return [Sequel::SQL::BooleanExpression]
    def expired_condition
      Sequel.|(inactive_condition, remember_lapsed_condition, lifetime_condition)
    end

    # The absolute session lifetime, in seconds since sign-in, or nil when
    # the operator has disabled it: `site.session.absolute_timeout`
    # (SESSION_ABSOLUTE_TIMEOUT), {DEFAULT_LIFETIME_DEADLINE} when unset.
    # Applied by this gate to the row's `created_at` (and handed to Rodauth
    # as `session_lifetime_deadline`, where nil means none) and by
    # Onetime::Session::RackStore to the blob's `authenticated_at`, so both auth modes
    # share the one bound.
    #
    # Read on every call, never memoised, so a config reload takes effect
    # without a restart. The value arrives as whatever YAML parsed from
    # `<%= ENV[...] || N %>`, so it is accepted only as a clean non-negative
    # integer (an Integer, or an all-digits String); anything else falls
    # back to the default rather than String#to_i-ing a typo into a
    # 12-second lifetime ("12h") or a disabled one ("off"). 0 legitimately
    # disables the bound, so it is kept, as nil. Same rule as the colonel's
    # AdminSessionLifetime timeouts.
    #
    # @return [Integer, nil]
    def lifetime_deadline
      raw     = Onetime.session_config['absolute_timeout']
      seconds =
        case raw
        when Integer then raw.negative? ? DEFAULT_LIFETIME_DEADLINE : raw
        when String  then raw.match?(/\A\d+\z/) ? raw.to_i : DEFAULT_LIFETIME_DEADLINE
        else DEFAULT_LIFETIME_DEADLINE
        end
      seconds.zero? ? nil : seconds
    rescue StandardError
      DEFAULT_LIFETIME_DEADLINE
    end

    private

    def compute(session, env = nil)
      return :skipped unless applicable?(session)

      db = ::Auth::Database.connection
      return unavailable(session, 'no auth database connection') if db.nil?

      row_ds = row_dataset(db, session)
      count(env, :queries)
      row    = row_ds.select(
        Sequel.as(flag(inactive_condition), :inactive),
        Sequel.as(flag(remember_lapsed_condition), :remember_lapsed),
        Sequel.as(flag(lifetime_condition), :outlived),
        Sequel.as(flag(past_condition(:last_use, TOUCH_INTERVAL)), :touch_due),
      ).first
      return revoked(session) if row.nil?
      return expire(row_ds, session, 'inactivity', env) if row[:inactive].to_i == 1
      return expire(row_ds, session, 'remember', env) if row[:remember_lapsed].to_i == 1
      return expire(row_ds, session, 'lifetime', env) if row[:outlived].to_i == 1

      record_activity(row_ds, session, env) if row[:touch_due].to_i == 1
      :active
    rescue StandardError => ex
      unavailable(session, "#{ex.class}: #{ex.message}")
    end

    def row_dataset(db, session)
      db[TABLE].where(
        account_id: session['account_id'],
        session_id: session['active_session_id_hmac'],
      )
    end

    # `last_use` is due a refresh. An activity request refreshes it; a
    # passive one leaves it alone (see the class docstring).
    def record_activity(row_ds, session, env)
      touch(row_ds, session, env) unless Session::Activity.passive?(env)
    end

    def count(env, key)
      return unless env.is_a?(Hash)

      stats       = (env[STATS_ENV_KEY] ||= { queries: 0, writes: 0 })
      stats[key] += 1
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

    # True when the row's timestamp `column` (`last_use` and `created_at` are
    # both NOT NULL in the schema) is more than `seconds` old. Evaluated by
    # the database against its own CURRENT_TIMESTAMP, never against Ruby's
    # clock. `Sequel.date_sub` comes from the date_arithmetic extension,
    # which Auth::Database loads on the authdb connection (Rodauth's
    # active_sessions feature needs it too).
    def past_condition(column, seconds)
      Sequel[column] < Sequel.date_sub(Sequel::CURRENT_TIMESTAMP, seconds: seconds)
    end

    # Idle past the inactivity deadline, for a row that is not remembered.
    # With remember-me switched off (AUTH_REMEMBER_ME_ENABLED=false) no row
    # is exempt: a stamp made before the switch no longer holds off the
    # inactivity deadline (it still ends the row when it lapses, below).
    def inactive_condition
      idle = past_condition(:last_use, INACTIVITY_DEADLINE)
      return idle unless Session::RememberMe.enabled?

      Sequel.&({ remember_until: nil }, idle)
    end

    # Remembered, and the remember deadline has passed. Not subject to the
    # switch: a deadline that has passed has passed, whatever the operator
    # has since decided about new sign-ins (the same rule the session store
    # applies to the blob's stamp, Onetime::Session::RackStore#find_session).
    def remember_lapsed_condition
      Sequel.&(Sequel.~(remember_until: nil), Sequel[:remember_until] < Sequel::CURRENT_TIMESTAMP)
    end

    # Older than the absolute lifetime; never true when the operator has
    # disabled it (absolute_timeout 0).
    def lifetime_condition
      deadline = lifetime_deadline
      return Sequel.lit('1 = 0') if deadline.nil?

      past_condition(:created_at, deadline)
    end

    # `1` or `0` for a condition, as an integer CASE rather than a bare
    # boolean because SQLite returns booleans as integers and Sequel only
    # typecasts declared boolean columns.
    def flag(condition)
      Sequel.case({ condition => 1 }, 0)
    end

    # The row is past the named deadline: remove it, as Rodauth's sweep
    # would, and refuse the Rack session. Removal is best effort, with its
    # own rescue: the SELECT has already decided, and a row this delete
    # cannot reach is collected by the sessions page's sweep instead.
    # Logged at info because the user sees a sign-out with no action of
    # their own behind it, and support needs to be able to name the deadline.
    def expire(row_ds, session, deadline, env = nil)
      OT.info "[active_session_gate] active-session row past its #{deadline} deadline; removed, Rack session refused #{who(session)}"
      forfeit_remember(session)
      count(env, :writes)
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
      forfeit_remember(session)
      :revoked
    end

    # A revoked Rack session stays in Redis (refuse, not destroy), and with
    # its remember-me deadline the blob and cookie would live on for up to
    # {Session::RememberMe::DURATION}. The row is the only thing refusing it, so a
    # later change that takes the gate out of play (simple mode, active
    # sessions off) would bring it back for that long. Dropping the stamp
    # returns the session to the default lifetime on this request's write:
    # a refused request is not activity, so the blob keeps at most the
    # default TTL (Onetime::Session::RackStore#expiration_for_write). Not done for
    # :unavailable, where the session is meant to be honoured again.
    def forfeit_remember(session)
      session.delete(Session::RememberMe::SESSION_KEY) if session.respond_to?(:delete)
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
    def touch(row_ds, session, env = nil)
      count(env, :writes)
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
