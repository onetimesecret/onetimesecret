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

    # Hard retention cap (by count). The primary memory bound: at most MAX_EVENTS
    # events are retained; on each write the oldest overflow is trimmed. Sized for a
    # deep-but-bounded operator trail; older history is expected to be shipped to an
    # external log sink if longer retention is required. Kept as a constant (not a
    # config key) so the audit path has no external configuration dependency.
    MAX_EVENTS = 10_000

    # Placeholder written in place of any redacted value.
    REDACTED = '[REDACTED]'

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
        event = {
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
        OT.le(
          '[AdminAuditEvent] record failed',
          exception: ex,
          verb: verb.to_s,
          target: target.to_s,
          result: result.to_s,
        )
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

      # @return [Integer] number of retained events.
      def count
        events.element_count
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

      private

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
