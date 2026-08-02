# lib/onetime/models/admin_audit_event.rb
#
# frozen_string_literal: true

module Onetime
  # AdminAuditEvent — the single write path every mutating admin operation calls.
  #
  # Every mutating admin op records who did what to whom and the result, so audit
  # logging is a property of the Operations layer rather than something bolted onto
  # each endpoint. An op passes actor/verb/target/result/detail; this model owns
  # storage, redaction, and capping. It knows nothing about HTTP or sessions — the
  # Operations contract (lib/onetime/operations/README.md) requires context-free
  # models.
  #
  # ## Backing store
  #
  # One global, capped Redis sorted set (`admin_audit_event:events`) via Familia.
  # Each event is a JSON payload stored as a member, scored by its creation time
  # (a high-precision float from Familia.now), so:
  #
  # - Reads are newest-first (revrange) for the admin audit view
  #   (GET /api/colonel/audit).
  # - The set is trimmed to MAX_EVENTS on every write. An unbounded audit set is a
  #   memory risk in Valkey (see epic D4) — the count cap is a hard memory bound.
  #
  # This mirrors the Feedback capped-sorted-set precedent (a class-level sorted set
  # trimmed on write, with no per-instance Horreum hashes that could orphan when the
  # index is trimmed).
  #
  # ## Redaction
  #
  # `record` never persists secret content, tokens, or passphrases. `detail` is run
  # through a defense-in-depth redaction pass (sensitive keys blanked, values
  # truncated, depth-bounded) before storage. Callers should still avoid handing
  # sensitive material to `detail` in the first place.
  #
  # ## Actor identity
  #
  # `actor` is a customer's public identity (extid or email), NEVER an internal
  # objid — internal ids must not leak into the audit trail. A Customer-like object
  # may be passed and its extid/email is extracted automatically.
  #
  # @example Record a successful role change from within an op's #call
  #   AdminAuditEvent.record(
  #     actor:  colonel.extid,
  #     verb:   'customer.set_role',
  #     target: customer.extid,
  #     result: :success,
  #     detail: { role: 'colonel' },
  #   )
  #
  class AdminAuditEvent < Familia::Horreum
    # No SCHEMA constant on purpose: this is a backend-only audit store with no
    # wire representation — it is never serialised into an API response, so there
    # is no frontend Zod shape to link to (unlike Customer/Secret/etc.). Declaring
    # `SCHEMA = 'models/admin_audit_event'` would point the schema-scanner at a
    # nonexistent `shapes/admin_audit_event`. Matches the Features /
    # OrganizationMembership precedent for non-serialised models. The read API
    # (GET /api/colonel/audit) declares its own wire contract instead: the logic
    # class links `response: 'colonelAuditEvents'`, whose Zod shape lives at
    # src/schemas/api/internal/responses/colonel-audit.ts.

    prefix :admin_audit_event

    # Global, bounded event history. member = JSON event payload, score = created
    # epoch seconds (float). This is a single site-wide admin audit trail, not a
    # per-customer collection.
    class_sorted_set :events

    # SECOND, SEPARATE RETENTION DOMAIN for security telemetry that an
    # UNAUTHENTICATED caller can trigger (see {.record_security}). Same member
    # shape and same score, different Redis key, different budget.
    #
    # Why a second collection rather than a bigger cap: the operator trail is
    # capped by COUNT and evicts oldest-first, so any writer an attacker can
    # drive competes with purge/role-change/suspension/impersonation records for
    # the same budget. Raising MAX_EVENTS moves the threshold without removing
    # the primitive. Splitting the budget removes it — no volume of anonymous
    # telemetry can evict a single privileged record, because the two sets are
    # trimmed independently.
    class_sorted_set :security_events

    # Hard retention cap (by count) for the OPERATOR trail. The primary memory
    # bound: at most MAX_EVENTS events are retained; on each write the oldest
    # overflow is trimmed. Sized for a deep-but-bounded operator trail; older
    # history is expected to be shipped to an external log sink if longer
    # retention is required. Kept as a constant (not a config key) so the audit
    # path has no external configuration dependency.
    #
    # WRITE-FREQUENCY INVARIANT, now STRUCTURAL rather than advisory. On a
    # count-capped set with no TTL, any event an attacker can mint on demand is a
    # log-eviction primitive: 10k such writes flush the real destructive-action
    # trail (purge, role change, suspension, impersonation). Per-writer rate
    # limiting is not a sufficient answer — the reset-request throttle bounds
    # itself to one event per bucket per lockout window, which still costs an
    # attacker only ~7.5 requests per evicted record once bucket minting is
    # cheap (distributed source, IPv6 prefix space, or a forgeable
    # client-IP header behind an appending proxy). So the boundary is enforced by
    # storage, not by frequency:
    #
    #   1. `events` (this cap) accepts AUTHENTICATED operator activity only, via
    #      {.record}. Every caller is an admin Operation.
    #   2. Anything an unauthenticated caller can trigger goes to
    #      `security_events` via {.record_security}, under MAX_SECURITY_EVENTS +
    #      SECURITY_EVENT_RETENTION. Flooding it evicts only other anonymous
    #      telemetry.
    #   3. Failure auditing ({Onetime::AuditedFailure}) still excludes bare
    #      authorization/authentication rejections outright — see
    #      AuditedFailure.authorization_rejection?, which also bars the
    #      LimitExceeded family by inheritance (LimitExceeded < Forbidden).
    #
    # So: a new verb reachable without authentication MUST use {.record_security}.
    # Both trails are merged newest-first for reading by
    # ColonelAPI::Logic::Colonel::ListAuditEvents, so the split costs no
    # queryability.
    MAX_EVENTS = 10_000

    # Retention cap (by count) for the anonymous security-telemetry trail. Small
    # on purpose: it holds detection signal, not a forensic record, and a
    # flooding attacker only ever evicts their own earlier events. An operator
    # who needs the full history ships these to an external sink (they are also
    # emitted as OT.le log lines at their call sites).
    MAX_SECURITY_EVENTS = 1_000

    # Age bound (seconds) for the security trail, trimmed by score on every
    # security write. `events` has no TTL because operator history is worth
    # keeping until the count cap forces eviction; anonymous telemetry goes stale,
    # so it gets both bounds. Sorted-set members cannot carry a per-member TTL, so
    # this is a ZREMRANGEBYSCORE over the creation score.
    SECURITY_EVENT_RETENTION = 7 * 24 * 60 * 60 # 7 days

    # Placeholder written in place of any redacted value.
    REDACTED = '[REDACTED]'

    # The one verb constant that lives on the model instead of on its emitter.
    #
    # Every other verb has exactly one emitter, which owns its own AUDIT_VERB.
    # Colonel session establishment has TWO, one per auth mode — full mode syncs
    # the session in Auth::Operations::SyncSession, simple mode never loads the
    # auth app at all and establishes it in
    # Core::Logic::Authentication::AuthenticateSession. Neither can reference the
    # other's constant, and the string must be identical in both (the admin
    # console filters on it), so it is single-sourced here.
    VERB_COLONEL_SIGNIN = 'colonel.signin'

    # Keys whose values must never be persisted verbatim. Matched case-insensitively
    # against stringified detail keys at any nesting depth. Defense-in-depth only —
    # the primary control is callers not passing secret content to `detail`.
    # `otp`/`pin` use letter-delimited lookarounds rather than `\b`: `\b` treats
    # `_` as a word char, so `\botp\b` would MISS snake_case keys like `otp_code`
    # / `user_pin`. The lookarounds match `otp`/`pin` as a whole segment (start,
    # end, or a non-letter delimiter such as `_`/`-`/digit) while still rejecting
    # embeddings like `caption`, `shipping`, `mapping`, `spindle`.
    SENSITIVE_KEY_PATTERN = /
      pass(word|phrase|code)? | token | secret | cipher | api[-_]?key |
      authorization | cookie | credential | private[-_]?key |
      (?<![a-z])otp(?![a-z]) | (?<![a-z])pin(?![a-z])
    /xi

    # Bounds on stored detail, to keep a single event small and predictable.
    MAX_DETAIL_VALUE_LENGTH = 256 # per string value
    MAX_DETAIL_KEYS         = 25  # per hash/array
    MAX_DETAIL_DEPTH        = 4   # nesting levels before collapsing to REDACTED

    class << self
      # Record a single audit event. The one write path for mutating admin ops.
      #
      # Best-effort by design: a failed audit write must never break the operation
      # that called it, so any error is logged and swallowed (returns nil). See the
      # fail-closed HOOK below — destructive verbs may later opt into re-raising.
      #
      # @param actor [String, #extid, #email] the acting colonel's PUBLIC identity
      #   (extid or email). Never pass an internal objid. A Customer-like object is
      #   accepted and its extid/email is extracted.
      # @param verb [String, Symbol] the operation name, e.g. 'customer.set_role'.
      # @param target [String, Symbol] the PUBLIC id of the affected resource.
      # @param result [String, Symbol] outcome, e.g. :success / :failure.
      # @param detail [Hash, String, nil] optional minimal context. Redacted before
      #   storage; never include secret content, tokens, or passphrases.
      # @return [Hash, nil] the stored event (string keys), or nil if the write failed.
      def record(actor:, verb:, target:, result:, detail: nil)
        event = build_event(actor: actor, verb: verb, target: target, result: result, detail: detail)

        events.add(event, event['created'])
        trim!
        event
      rescue StandardError => ex
        # Fail-open: never let audit-write failure break the caller.
        #
        # HOOK (epic D4): destructive verbs (purge, delete, impersonate) may later
        # choose fail-closed here — re-raise / abort the op when its audit event
        # cannot be written, so a destructive action is never taken silently. Today
        # every verb is fail-open.
        log_record_failure(ex, verb, target, result)
        nil
      end

      # Record one SECURITY-TELEMETRY event: same shape as {.record}, stored in
      # the separate `security_events` collection with its own count cap and age
      # bound.
      #
      # Use this — never {.record} — for any event an UNAUTHENTICATED caller can
      # cause. The separation is the control described in the WRITE-FREQUENCY
      # INVARIANT above: writes here can never evict an operator record, so a
      # caller does not have to argue that its own rate limiting is tight enough
      # to protect the operator trail. Callers should still bound their write
      # rate for signal quality (a per-request event is noise), but that is no
      # longer load-bearing for the integrity of `events`.
      #
      # Same best-effort contract as {.record}: errors are logged and swallowed.
      #
      # @return [Hash, nil] the stored event (string keys), or nil if it failed.
      def record_security(actor:, verb:, target:, result:, detail: nil)
        event = build_event(actor: actor, verb: verb, target: target, result: result, detail: detail)

        security_events.add(event, event['created'])
        trim_security!
        event
      rescue StandardError => ex
        log_record_failure(ex, verb, target, result)
        nil
      end

      # Newest-first slice of the audit trail. Backs the admin audit view
      # (GET /api/colonel/audit via ColonelAPI::Logic::Colonel::ListAuditEvents).
      #
      # @param limit [Integer] max events to return (most recent first).
      # @param offset [Integer] rank offset into the newest-first ordering
      #   (0 = the newest event), enabling page reads without loading the set.
      # @return [Array<Hash>] events with string keys, newest first.
      def recent(limit = 100, offset = 0)
        limit  = limit.to_i
        offset = offset.to_i
        return [] if limit <= 0

        offset = 0 if offset.negative?
        events.revrange(offset, offset + limit - 1)
      end

      # Newest-first slice of the SECURITY-TELEMETRY trail. Same contract as
      # {.recent}, over the separate collection.
      #
      # @param limit [Integer] max events to return (most recent first).
      # @param offset [Integer] rank offset into the newest-first ordering.
      # @return [Array<Hash>] events with string keys, newest first.
      def recent_security(limit = 100, offset = 0)
        limit  = limit.to_i
        offset = offset.to_i
        return [] if limit <= 0

        offset = 0 if offset.negative?
        security_events.revrange(offset, offset + limit - 1)
      end

      # @return [Integer] number of retained events.
      def count
        events.element_count
      end

      # @return [Integer] number of retained security-telemetry events.
      def security_count
        security_events.element_count
      end

      # Enforce the count cap: keep only the newest `cap` events, dropping the
      # oldest overflow. Runs on every write; also callable directly.
      #
      # Members are scored by creation time (ascending), so the newest sit at the
      # highest ranks. Removing ranks 0..-(cap+1) drops everything but the last
      # `cap`. When count <= cap this is a no-op (Redis removes nothing).
      #
      # @param cap [Integer] number of newest events to retain.
      # @return [Integer] number of events removed.
      def trim!(cap = MAX_EVENTS)
        cap = cap.to_i
        return 0 if cap.negative?

        events.remrangebyrank(0, -(cap + 1))
      end

      # Enforce BOTH bounds on the security-telemetry trail: the count cap (as
      # {.trim!}) and the age bound, which is applied by score because sorted-set
      # members cannot carry an individual TTL. Runs on every security write.
      #
      # @param cap [Integer] number of newest security events to retain.
      # @param max_age [Integer] seconds; events older than this are dropped.
      #   Non-positive disables the age bound (the count cap still applies).
      # @return [Integer] number of events removed by both passes.
      def trim_security!(cap = MAX_SECURITY_EVENTS, max_age = SECURITY_EVENT_RETENTION)
        cap = cap.to_i
        return 0 if cap.negative?

        removed = security_events.remrangebyrank(0, -(cap + 1)).to_i

        max_age = max_age.to_i
        return removed unless max_age.positive?

        # Scores are creation times, so everything scored at or below the cutoff
        # is older than the retention window. Starting at 0 rather than '-inf' is
        # safe: every score this model writes is an epoch time.
        removed + security_events.remrangebyscore(0, Familia.now - max_age).to_i
      end

      private

      # Build the stored member. Shared by {.record} and {.record_security} so the
      # two trails can never drift in shape (the read path merges them).
      def build_event(actor:, verb:, target:, result:, detail:)
        {
          'actor' => normalize_actor(actor),
          'verb' => verb.to_s,
          'target' => target.to_s,
          'result' => result.to_s,
          'detail' => redact(detail),
          'created' => Familia.now,
          # Nonce: keeps otherwise-identical events distinct members in the sorted
          # set (a duplicate member would collide and silently drop one event).
          'id' => Familia.generate_id,
        }
      end

      def log_record_failure(ex, verb, target, result)
        OT.le(
          '[AdminAuditEvent] record failed',
          exception: ex,
          verb: verb.to_s,
          target: target.to_s,
          result: result.to_s,
        )
      end

      # Coerce actor to a public identity string, preferring extid then email, and
      # never an internal objid. Accepts a bare String (the common case) or a
      # Customer-like object.
      def normalize_actor(actor)
        return 'unknown' if actor.nil?

        if actor.respond_to?(:extid) && !actor.extid.to_s.empty?
          actor.extid.to_s
        elsif actor.respond_to?(:email) && !actor.email.to_s.empty?
          actor.email.to_s
        else
          actor.to_s
        end
      end

      # Defense-in-depth redaction of caller-supplied detail. Blanks values under
      # sensitive keys at any depth, truncates long strings, bounds width and depth,
      # and preserves numeric/boolean types for JSON fidelity.
      def redact(detail, depth = 0)
        case detail
        when nil
          nil
        when Hash
          return REDACTED if depth > MAX_DETAIL_DEPTH

          detail.first(MAX_DETAIL_KEYS).each_with_object({}) do |(key, value), acc|
            key_str      = key.to_s
            acc[key_str] = if SENSITIVE_KEY_PATTERN.match?(key_str)
              REDACTED
            else
              redact(value, depth + 1)
            end
          end
        when Array
          return REDACTED if depth > MAX_DETAIL_DEPTH

          detail.first(MAX_DETAIL_KEYS).map { |value| redact(value, depth + 1) }
        when Numeric, TrueClass, FalseClass
          detail
        else
          truncate_value(detail.to_s)
        end
      end

      # Truncate an overlong string value, marking that it was clipped.
      def truncate_value(value)
        str = value.to_s
        return str if str.length <= MAX_DETAIL_VALUE_LENGTH

        "#{str[0, MAX_DETAIL_VALUE_LENGTH]}..."
      end
    end
  end
end
