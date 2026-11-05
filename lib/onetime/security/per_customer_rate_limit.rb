# lib/onetime/security/per_customer_rate_limit.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'

module Onetime
  module Security
    # PerCustomerRateLimit - the engine behind the per-customer action caps
    #
    # A small cap on how often ONE authenticated customer may fire an action
    # that reaches outside this system (a token request to an identity
    # provider, a real email through the delivery provider). Each such action
    # has a thin limiter module ({SsoDiagnosticsRateLimiter},
    # {SenderTestEmailRateLimiter}) that declares a {Policy} and calls
    # {.enforce!}; everything else — the Lua script, the key shape, the config
    # reading, the cap-hit audit event — is here, so the limiters cannot drift
    # from one another.
    #
    # KEYED ON cust.extid, the acting customer's PUBLIC id — the same value
    # every logic class returns as user_id and the audit trail records as
    # actor. Per CUSTOMER rather than per resource: what is bounded is one
    # actor's volume, and a per-domain bucket would hand an owner with several
    # domains a fresh budget per domain.
    #
    # Same contract as {CreateAccountRateLimiter}: one atomic Lua round trip
    # checks the lockout and records the request; the request that reaches
    # the cap is itself ALLOWED and sets the lockout; later requests are
    # denied before incrementing. Call it from the END of raise_concerns —
    # after the session, ownership and entitlement guards and after the
    # target record is found — so a refused request costs nothing.
    #
    # NEVER interpolate a session id — Rack aliases SessionId#to_s to the live
    # bearer cookie (#4330). The extid is a public identifier.
    #
    # Fail-closed on Redis errors, like every sibling limiter: an outage 500s
    # the action rather than admitting an unthrottled one.
    #
    # Redis keys (string keys at the Redis boundary; Customer shard):
    #   - {kind}:attempts:{extid}  - per-customer counter
    #   - {kind}:locked:{extid}    - per-customer lockout flag
    # Each kind needs a byte-identical row in
    # Onetime::Operations::RateLimit::Registry::LIMITERS, or the CLI, Inspect
    # and Reset cannot see the keys.
    #
    # Config (features.organizations.<config_key>): enabled,
    # max_per_customer, window, lockout. Absent config -> enabled with the
    # policy's defaults; set enabled:false to disable.
    module PerCustomerRateLimit
      # One limiter's identity and defaults.
      #
      # kind         registry kind and Redis key prefix
      # config_key   key under features.organizations
      # default_*    fallbacks for absent, zero or garbage settings
      # audit_verb   verb of the cap-hit event (security trail)
      # message      LimitExceeded message (the API error body)
      # log_tag      log prefix, the limiter module's name
      # action_noun  plural noun for the near-cap log line ("runs", "sends")
      Policy = Data.define(
        :kind,
        :config_key,
        :default_max_per_customer,
        :default_window,
        :default_lockout,
        :audit_verb,
        :message,
        :log_tag,
        :action_noun,
      )

      # Checks the lockout AND records the request in one atomic round trip —
      # byte-identical in contract to
      # {CreateAccountRateLimiter::CHECK_AND_RECORD_SCRIPT}: the increment that
      # reaches max_attempts sets the lockout flag and clears the counter, and
      # every later execution sees the flag and is denied before incrementing,
      # so concurrent bursts cannot overshoot the cap.
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

      extend self

      # Enforce the policy's per-customer limit and record this request.
      # Raises LimitExceeded when the customer is locked; a locked bucket is
      # never incremented (the Lua script denies before INCR). No-op when the
      # limiter is disabled by config, without inspecting the subject. A blank
      # subject is refused rather than skipped: the call site has already
      # required an authenticated customer, so a missing extid is a
      # programming error, and a shared blank-key bucket would lock every such
      # caller out together.
      #
      # @param policy [Policy]
      # @param customer_extid [String] The acting customer's public id.
      # @raise [ArgumentError] If the subject is blank.
      # @raise [Onetime::LimitExceeded] If the limit is exceeded.
      # @return [void]
      def enforce!(policy, customer_extid)
        return unless enabled?(policy)

        subject = customer_extid.to_s
        raise ArgumentError, "#{policy.log_tag} needs a customer extid" if subject.empty?

        max             = max_per_customer(policy)
        lockout         = lockout(policy)
        keys            = keys_for(policy, subject)
        allowed, detail = redis.eval(
          CHECK_AND_RECORD_SCRIPT,
          keys: [keys[:attempts], keys[:lockout]],
          argv: [window(policy), max, lockout],
        )

        if allowed.to_i != 1
          raise Onetime::LimitExceeded.new(
            policy.message,
            retry_after: detail.to_i.positive? ? detail.to_i : lockout,
            max_attempts: max,
          )
        end

        count = detail.to_i
        if count >= max
          # This cap-reaching request was itself ALLOWED (the Lua script locks
          # after incrementing); the lockout applies to the next one.
          OT.le "[#{policy.log_tag}] customer #{subject} hit cap (#{count}/#{max}); locked for #{lockout}s"
          record_throttle_audit(policy, subject, count)
        elsif count >= max - 2
          OT.li "[#{policy.log_tag}] customer #{subject} at #{count}/#{max} #{policy.action_noun}"
        end
      end

      # Cap-reaching request only — one event per customer per lockout window —
      # in the SECURITY trail (count-capped with an age bound), never the
      # operator trail. Best-effort, matching every other audit call site: a
      # throttle must never fail because its event could not be assembled.
      def record_throttle_audit(policy, subject, count)
        Onetime::ColonelAuditEvent.record_security(
          actor: subject,
          verb: policy.audit_verb,
          target: subject,
          result: :failure,
          detail: {
            count: count,
            max_attempts: max_per_customer(policy),
            window: window(policy),
            lockout: lockout(policy),
          },
        )
      rescue StandardError => ex
        OT.le("[#{policy.log_tag}] audit record failed", exception: ex)
      end

      def keys_for(policy, subject)
        {
          attempts: "#{policy.kind}:attempts:#{subject}",
          lockout: "#{policy.kind}:locked:#{subject}",
        }
      end

      # Co-located with the Customer shard because the subject is a Customer
      # extid (matches login / reset / create_account / colonel).
      def redis
        Onetime::Customer.dbclient
      end

      def config(policy)
        OT.conf.dig('features', 'organizations', policy.config_key) || {}
      end

      # Enabled unless config explicitly sets enabled:false. Absent config
      # keeps the protective default on.
      def enabled?(policy)
        config(policy).fetch('enabled', true) != false
      end

      def max_per_customer(policy)
        positive_setting(policy, 'max_per_customer', policy.default_max_per_customer)
      end

      def window(policy)
        positive_setting(policy, 'window', policy.default_window)
      end

      def lockout(policy)
        positive_setting(policy, 'lockout', policy.default_lockout)
      end

      # Fall back to the default unless the configured value coerces to a
      # POSITIVE integer. A zero or garbage value would otherwise invert
      # enforcement: a zero cap locks on the first request, and a non-positive
      # lockout makes the Lua SETEX fail, turning every request into a 500.
      #
      # Coerced through a string: YAML parses `false`, `true` and `12.5`
      # as FalseClass, TrueClass and Float, none of which responds to to_i
      # the way an env-var string does (false.to_i raises), and a raise here
      # would 500 every request. Base 10 so "010" is ten, not octal.
      def positive_setting(policy, key, default)
        value = Integer(config(policy)[key].to_s, 10, exception: false)
        value&.positive? ? value : default
      end
    end
  end
end
