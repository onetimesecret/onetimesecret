# lib/onetime/security/colonel_rate_limiter.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'

module Onetime
  module Security
    # Rate limits for the colonel (admin) API surface — the first limiter in the
    # repo that keys on an AUTHENTICATED identity rather than a perimeter IP.
    #
    # #4327 ships the elevation bucket only. #4329 adds the broad mutation
    # bucket, the tight destructive bucket and the handle-resolve bucket to the
    # same module, through the same {#enforce_colonel_bucket!} body.
    #
    # KEYED ON cust.extid, the acting colonel's PUBLIC id — the same value every
    # colonel op already passes as its audit `actor:`. Per-ACCOUNT rather than
    # per-session because a per-session bucket is strictly weaker: it bounds one
    # cookie's activity, and an attacker with any second way in (a second stolen
    # session, a parallel tab, the CLI) gets a fresh budget, while the account
    # bucket bounds the identity as a whole and lines up with the audit actor.
    # Issue #4329 asks for "a modest per-session limiter"; this deliberately
    # goes stronger, and the PR says so.
    #
    # NEVER interpolate sess.id — Rack aliases SessionId#to_s to #public_id, i.e.
    # the live bearer cookie, which would leak credentials into
    # `ratelimit inspect`, `bin/ots ratelimit keys`, `redis-cli --scan` and the
    # audit target field (#4330).
    #
    # Fail-closed on Redis errors, matching every sibling limiter: an outage 500s
    # a colonel mutation rather than admitting an unthrottled one.
    #
    # CLEARING A STUCK LOCKOUT — the same two paths as every other limiter, over
    # kinds `colonel_elevation`, `colonel_mutation`, `colonel_destructive` and
    # `colonel_handle_resolve`:
    #
    #   1. `bin/ots ratelimit keys <kind> <extid>` piped to valkey-cli (the CLI
    #      only PRINTS the commands);
    #   2. `POST /api/colonel/ratelimit/reset` with that kind, which performs the
    #      delete AND records a ColonelAuditEvent. That endpoint is TIER 2 —
    #      confirmation only, no elevation — so an operator locked out of step-up
    #      or of destructive actions can still clear their own bucket. It is
    #      itself a mutation, so the one bucket it cannot rescue you from is
    #      `colonel_mutation`; that is what the valkey-cli path is for.
    #
    # Usage:
    #   include Onetime::Security::ColonelRateLimiter
    #   enforce_colonel_elevation_limit!(cust.extid)
    module ColonelRateLimiter
      # Five step-up attempts per 15 minutes, then a 15-minute lockout. Tight on
      # purpose: Auth::Config.valid_login_and_password? is an INTERNAL REQUEST,
      # so it is not a login (no after_login hook, no auth audit) and it does not
      # increment Rodauth's own lockout counter — this limiter is the only
      # backstop against password guessing through POST /api/colonel/elevation.
      DEFAULT_ELEVATION_MAX     = 5
      DEFAULT_ELEVATION_WINDOW  = 900
      DEFAULT_ELEVATION_LOCKOUT = 900

      # Namespaced `<resource>.<action>` like every other verb in the trail; the
      # admin console filters on the exact string, so it is a constant.
      ELEVATION_AUDIT_VERB = 'colonel.elevate_throttled'

      # 120 mutating colonel requests per 5 minutes (#4329). Far above any human
      # operator's rate and above a bulk console session, so this bucket only
      # trips on scripted abuse. It bounds request VOLUME across all 46 mutating
      # verbs and is the ONLY bucket charged before the guards run — see
      # ColonelAPI::Logic::Base#initialize.
      DEFAULT_MUTATION_MAX     = 120
      DEFAULT_MUTATION_WINDOW  = 300
      DEFAULT_MUTATION_LOCKOUT = 300
      MUTATION_AUDIT_VERB      = 'colonel.mutation_throttled'

      # 10 TIER 1 actions per 5 minutes, then a 15-minute lockout. Permits a real
      # incident-response burst (revoke a handful of sessions, purge an account)
      # while capping a scripted purge at 10 before it stalls — which keeps the
      # audit trail's 10 000-event count cap unreachable inside a lockout window.
      # That is the whole point of #4329: a purge at wire speed can otherwise
      # evict the evidence of its own actions.
      #
      # These are 10 EXECUTABLE attempts, not 10 requests: the charge is the last
      # line of raise_concerns, after elevation, confirmation and the interlocks
      # all pass, so a rejected attempt costs nothing and an attacker holding the
      # cookie cannot burn the real operator's budget with cheap 403s.
      DEFAULT_DESTRUCTIVE_MAX     = 10
      DEFAULT_DESTRUCTIVE_WINDOW  = 300
      DEFAULT_DESTRUCTIVE_LOCKOUT = 900
      DESTRUCTIVE_AUDIT_VERB      = 'colonel.destructive_throttled'

      # 60 session-handle lookups per 5 minutes. The two handle-resolving session
      # reads are the only colonel READS whose cost is not O(1)-ish — each can
      # fall back to a bounded 10 000-key SCAN plus up to 10 000 HMACs (#4330) —
      # so they carry a bucket while every other read stays unlimited (the
      # console fetches those, and a limiter there would break the dashboard).
      DEFAULT_HANDLE_RESOLVE_MAX     = 60
      DEFAULT_HANDLE_RESOLVE_WINDOW  = 300
      DEFAULT_HANDLE_RESOLVE_LOCKOUT = 300
      HANDLE_RESOLVE_AUDIT_VERB      = 'colonel.handle_resolve_throttled'

      # Check the lockout AND record the attempt in one atomic round trip — the
      # same contract as every sibling limiter: Redis serializes script
      # executions, the increment that reaches max_attempts sets the lockout flag
      # and clears the counter, and every later execution sees the flag and is
      # denied before incrementing, so concurrent bursts cannot overshoot.
      # Returns {1, current_count} when allowed, {0, lockout_ttl} when denied.
      CHECK_AND_RECORD_SCRIPT = <<~LUA
        local attempts_key = KEYS[1]
        local lockout_key = KEYS[2]
        local attempt_window = tonumber(ARGV[1])
        local max_attempts = tonumber(ARGV[2])
        local lockout_duration = tonumber(ARGV[3])

        if redis.call('EXISTS', lockout_key) == 1 then
          return {0, redis.call('TTL', lockout_key)}
        end

        local current = redis.call('INCR', attempts_key)

        if current == 1 then
          redis.call('EXPIRE', attempts_key, attempt_window)
        end

        if current >= max_attempts then
          redis.call('SETEX', lockout_key, lockout_duration, '1')
          redis.call('DEL', attempts_key)
        end

        return {1, current}
      LUA

      # Throttle step-up attempts for one colonel account.
      #
      # @param subject [String, nil] the acting colonel's extid.
      # @raise [Onetime::LimitExceeded] 429 once the account is locked out.
      # @return [void]
      def enforce_colonel_elevation_limit!(subject)
        enforce_colonel_bucket!(
          prefix: 'colonel:elevation',
          subject: subject,
          max_attempts: colonel_elevation_max,
          window: colonel_elevation_window,
          lockout: colonel_elevation_lockout,
          enabled: colonel_elevation_limit_enabled?,
          message: 'Too many step-up attempts. Try again later.',
          audit_verb: ELEVATION_AUDIT_VERB,
        )
      end

      # Throttle every mutating colonel request for one colonel account (#4329).
      # Charged from ColonelAPI::Logic::Base#initialize, so all 46 mutating verbs
      # are covered without editing 46 files.
      #
      # @param subject [String, nil] the acting colonel's extid.
      # @raise [Onetime::LimitExceeded] 429 once the account is locked out.
      # @return [void]
      def enforce_colonel_mutation_limit!(subject)
        enforce_colonel_bucket!(
          prefix: 'colonel:mutation',
          subject: subject,
          max_attempts: colonel_mutation_max,
          window: colonel_mutation_window,
          lockout: colonel_mutation_lockout,
          enabled: colonel_mutation_limit_enabled?,
          message: 'Too many admin actions. Please slow down and try again shortly.',
          audit_verb: MUTATION_AUDIT_VERB,
        )
      end

      # Throttle TIER 1 (destructive) colonel actions for one colonel account.
      # Charged as the LAST line of raise_concerns — see
      # ColonelAPI::Logic::DestructiveAction#charge_destructive_budget!.
      #
      # @param subject [String, nil] the acting colonel's extid.
      # @raise [Onetime::LimitExceeded] 429 once the account is locked out.
      # @return [void]
      def enforce_colonel_destructive_limit!(subject)
        enforce_colonel_bucket!(
          prefix: 'colonel:destructive',
          subject: subject,
          max_attempts: colonel_destructive_max,
          window: colonel_destructive_window,
          lockout: colonel_destructive_lockout,
          enabled: colonel_destructive_limit_enabled?,
          message: 'Too many destructive admin actions. This is a safety limit; ' \
                   'try again shortly or use the CLI for bulk work.',
          audit_verb: DESTRUCTIVE_AUDIT_VERB,
        )
      end

      # Throttle the two session reads that resolve an opaque handle (#4330) and
      # may fall back to a bounded keyspace scan.
      #
      # @param subject [String, nil] the acting colonel's extid.
      # @raise [Onetime::LimitExceeded] 429 once the account is locked out.
      # @return [void]
      def enforce_colonel_handle_resolve_limit!(subject)
        enforce_colonel_bucket!(
          prefix: 'colonel:handle_resolve',
          subject: subject,
          max_attempts: colonel_handle_resolve_max,
          window: colonel_handle_resolve_window,
          lockout: colonel_handle_resolve_lockout,
          enabled: colonel_handle_resolve_limit_enabled?,
          message: 'Too many session lookups. Try again shortly.',
          audit_verb: HANDLE_RESOLVE_AUDIT_VERB,
        )
      end

      private

      # Shared body for every colonel bucket.
      #
      # Skips entirely on a blank subject rather than building one shared
      # blank-suffixed key: the first few subject-less callers would lock that
      # bucket and every later one would be denied — a colonel-wide outage driven
      # by whatever made the extid unresolvable. Same rationale as
      # CreateAccountRateLimiter#create_account_ip_keys. On this surface the
      # router has already enforced role=colonel, so an authenticated caller with
      # no extid is not a reachable state.
      def enforce_colonel_bucket!(prefix:, subject:, max_attempts:, window:, lockout:,
                                  enabled:, message:, audit_verb:)
        return unless enabled
        return if subject.to_s.empty?

        allowed, detail = colonel_rate_limit_redis.eval(
          CHECK_AND_RECORD_SCRIPT,
          keys: ["#{prefix}:attempts:#{subject}", "#{prefix}:locked:#{subject}"],
          argv: [window, max_attempts, lockout],
        )

        if allowed.to_i != 1
          raise Onetime::LimitExceeded.new(
            message,
            retry_after: detail.to_i.positive? ? detail.to_i : lockout,
            max_attempts: max_attempts,
          )
        end

        return unless detail.to_i >= max_attempts

        # This cap-reaching request was itself ALLOWED (the Lua script locks
        # after incrementing); the lockout applies to the next one.
        OT.le "[ColonelRateLimiter] #{prefix} subject #{subject} hit cap " \
              "(#{detail.to_i}/#{max_attempts}); locked for #{lockout}s"
        record_colonel_throttle_audit(audit_verb, subject, detail.to_i, max_attempts, window, lockout)
      end

      # Cap-reaching request only — one event per colonel per lockout window.
      #
      # record_security (1k cap + 7d retention), never .record: the #4327/#4329
      # threat model is a COMPROMISED COLONEL SESSION, i.e. exactly an actor who
      # can mint authenticated events on demand, and the operator trail .record
      # writes to is count-capped with no TTL.
      #
      # Best-effort, matching every other audit call site: a throttle must never
      # fail because its event could not be assembled.
      def record_colonel_throttle_audit(verb, subject, count, max, window, lockout)
        Onetime::ColonelAuditEvent.record_security(
          actor: subject,
          verb: verb,
          target: subject,
          result: :failure,
          detail: { count: count, max_attempts: max, window: window, lockout: lockout },
        )
      rescue StandardError => ex
        OT.le('[ColonelRateLimiter] audit record failed', exception: ex)
      end

      # Co-located with the Customer shard because the subject is a Customer
      # extid (matches login / reset / create_account).
      def colonel_rate_limit_redis
        Onetime::Customer.dbclient
      end

      def colonel_rate_limit_config
        OT.conf.dig('site', 'admin', 'rate_limit') || {}
      end

      # Every bucket consults the PARENT flag as well as its own, so
      # `site.admin.rate_limit.enabled: false` (what spec/config.test.yaml sets)
      # short-circuits all of them — otherwise the colonel suites, which drive
      # many endpoints from one process as one actor, would throttle themselves.
      def colonel_elevation_limit_enabled?
        colonel_bucket_enabled?('elevation')
      end

      def colonel_mutation_limit_enabled?
        colonel_bucket_enabled?('mutation')
      end

      def colonel_destructive_limit_enabled?
        colonel_bucket_enabled?('destructive')
      end

      def colonel_handle_resolve_limit_enabled?
        colonel_bucket_enabled?('handle_resolve')
      end

      def colonel_bucket_enabled?(section)
        return false if colonel_rate_limit_config.fetch('enabled', true) == false

        colonel_rate_limit_config.dig(section, 'enabled') != false
      end

      # Fall back to the default unless the configured value coerces to a
      # POSITIVE integer. A zero/garbage value (a typo'd env var: `to_i` turns
      # "abc" into 0) would otherwise invert enforcement — a zero cap locks on
      # the first attempt, and a non-positive lockout makes the Lua SETEX fail,
      # turning every step-up into a 500 instead of a throttle.
      def positive_colonel_setting(section, key, default)
        value = colonel_rate_limit_config.dig(section, key).to_i
        value.positive? ? value : default
      end

      def colonel_elevation_max
        positive_colonel_setting('elevation', 'max_attempts', DEFAULT_ELEVATION_MAX)
      end

      def colonel_elevation_window
        positive_colonel_setting('elevation', 'window', DEFAULT_ELEVATION_WINDOW)
      end

      def colonel_elevation_lockout
        positive_colonel_setting('elevation', 'lockout', DEFAULT_ELEVATION_LOCKOUT)
      end

      def colonel_mutation_max
        positive_colonel_setting('mutation', 'max_attempts', DEFAULT_MUTATION_MAX)
      end

      def colonel_mutation_window
        positive_colonel_setting('mutation', 'window', DEFAULT_MUTATION_WINDOW)
      end

      def colonel_mutation_lockout
        positive_colonel_setting('mutation', 'lockout', DEFAULT_MUTATION_LOCKOUT)
      end

      def colonel_destructive_max
        positive_colonel_setting('destructive', 'max_attempts', DEFAULT_DESTRUCTIVE_MAX)
      end

      def colonel_destructive_window
        positive_colonel_setting('destructive', 'window', DEFAULT_DESTRUCTIVE_WINDOW)
      end

      def colonel_destructive_lockout
        positive_colonel_setting('destructive', 'lockout', DEFAULT_DESTRUCTIVE_LOCKOUT)
      end

      def colonel_handle_resolve_max
        positive_colonel_setting('handle_resolve', 'max_attempts', DEFAULT_HANDLE_RESOLVE_MAX)
      end

      def colonel_handle_resolve_window
        positive_colonel_setting('handle_resolve', 'window', DEFAULT_HANDLE_RESOLVE_WINDOW)
      end

      def colonel_handle_resolve_lockout
        positive_colonel_setting('handle_resolve', 'lockout', DEFAULT_HANDLE_RESOLVE_LOCKOUT)
      end
    end
  end
end
