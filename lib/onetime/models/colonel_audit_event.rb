# lib/onetime/models/colonel_audit_event.rb
#
# frozen_string_literal: true

# Onetime::AuditWriteFailure is raised by the fail-closed branch of {.record}.
# Required explicitly because this file is loaded directly by ops and CLI
# commands that run outside the app autoloaders (same reason those files
# require this one).
require_relative '../errors'

# The event-time sink writes through a dedicated SemanticLogger category. The
# app boot configures SemanticLogger long before any audit write, but this file
# is also loaded directly by ops and CLI commands, so require the library here
# rather than assume the initializer ran.
require 'semantic_logger'

module Onetime
  # ColonelAuditEvent — the single write path every mutating admin operation calls.
  #
  # Every mutating admin op records who did what to whom and the result, so audit
  # logging is a property of the Operations layer rather than something bolted onto
  # each endpoint. An op passes actor/verb/target/result/detail; this model owns
  # storage, redaction, and capping. It knows nothing about HTTP or sessions — the
  # Operations contract (lib/onetime/operations/README.md) requires context-free
  # models.
  #
  # ## Two destinations: a durable sink and a queryable cache (#4334)
  #
  # Every event goes to BOTH, in this order:
  #
  #   1. THE SINK — a structured log line on the dedicated `ColonelAudit`
  #      SemanticLogger category, emitted BEFORE the datastore write. This is
  #      the DURABILITY STORY. It is append-only from this process's point of
  #      view, it leaves the process immediately (stdout by default, plus an
  #      optional syslog appender — see
  #      lib/onetime/initializers/setup_loggers.rb), and nothing in this
  #      codebase can retract a line once written. An operator who needs
  #      retention beyond the caps below, or a copy an application bug cannot
  #      reach, ships that stream.
  #
  #   2. THE CACHE — the capped Redis sorted sets described next. This is what
  #      the console and CLI query: recent, filterable, and bounded. It is not
  #      the archive, and it was never sized to be one.
  #
  # The ORDER is the point. Emitting first means a Valkey outage, an eviction,
  # or a trim cannot lose the record — the line is already gone to the sink. The
  # two are also independent: a sink failure is caught and logged and never
  # breaks the datastore write or the caller, and a datastore failure never
  # un-emits the sink line (that is what makes fail-closed survivable —
  # see the write-failure section below).
  #
  # ## Backing store (the cache half)
  #
  # One global, capped Redis sorted set (`colonel_audit_event:events`) via Familia.
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
  # ## No destructive primitive in the audit API (#4334)
  #
  # {.trim!}, {.trim_security!} and {.trim_access!} CLAMP their arguments: a cap
  # below the configured constant is raised to it, and a max_age below the
  # trail's retention constant is raised to it. Retention can therefore only ever
  # WIDEN through this API — `trim!(0)`, which used to empty the operator trail
  # in one call, is now a no-op. Narrowing retention means editing the
  # constants, which is a code change in review, not a call an attacker or a
  # stray script can make.
  #
  # This is a bound on THIS class's API, stated honestly: the underlying Familia
  # collections are still reachable (`ColonelAuditEvent.events.clear`), which is
  # what test setup and deliberate operator surgery use. No application code
  # calls it, and the sink half above is unaffected by anything done to Redis.
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
  # ## Write-failure posture: fail-open by default, fail-closed for destruction
  #
  # {.record} swallows its own errors and returns nil, because a broken audit
  # write must not break the operation that called it. That default is wrong for
  # exactly one class of verb: a purge, delete, role change, revoke or
  # suspension that completes with NO trail is an untraceable destructive
  # action. Those call sites pass `fail_closed: true` and get
  # {Onetime::AuditWriteFailure} instead of a silent nil (#4333).
  #
  # Be precise about what that buys, because the ordering does not change:
  # nearly every call site records AFTER its mutation, so fail-closed does NOT
  # roll anything back and does not prevent the destruction. What it does is
  # refuse to report success: the operator gets a hard failure naming the verb
  # and target, which is the signal that this action needs to be reconstructed
  # from the sink (see above — the line is already emitted when this fires) or
  # from the acting operator, rather than a green
  # response and an empty trail. Any op that wants prevention has to record
  # BEFORE it mutates; none does today.
  #
  # {.record_security} is fail-open ALWAYS and takes no such keyword. Its
  # writers are reachable by unauthenticated callers, and a fail-closed
  # security write would hand those callers an abort primitive over the code
  # path that logged them.
  #
  # {.record_access} is fail-open ALWAYS too, for a different reason: its
  # writers mutated nothing, so there is no destroyed-with-no-trail outcome for
  # fail-closed to surface — only the chance to take the console down over a
  # broken audit write while an operator is trying to read something.
  #
  # @example Record a successful role change from within an op's #call
  #   ColonelAuditEvent.record(
  #     actor:  colonel.extid,
  #     verb:   'customer.set_role',
  #     target: customer.extid,
  #     result: :success,
  #     detail: { role: 'colonel' },
  #   )
  #
  class ColonelAuditEvent < Familia::Horreum
    # No SCHEMA constant on purpose: this is a backend-only audit store with no
    # wire representation — it is never serialised into an API response, so there
    # is no frontend Zod shape to link to (unlike Customer/Secret/etc.). Declaring
    # `SCHEMA = 'models/colonel_audit_event'` would point the schema-scanner at a
    # nonexistent `shapes/colonel_audit_event`. Matches the Features /
    # OrganizationMembership precedent for non-serialised models. The read API
    # (GET /api/colonel/audit) declares its own wire contract instead: the logic
    # class links `response: 'colonelAuditEvents'`, whose Zod shape lives at
    # src/schemas/api/internal/responses/colonel-audit.ts. Its sibling
    # GET /api/colonel/audit/export has no Zod shape either — a CSV/NDJSON
    # download is not a JSON envelope; see that file's note.

    prefix :colonel_audit_event

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

    # THIRD RETENTION DOMAIN: authenticated NON-MUTATING OBSERVATIONS (#4335).
    # Same member shape, same score, its own Redis key, its own budget.
    #
    # What lands here, and the CURATION PRINCIPLE. Not every colonel GET —
    # roughly 25 read endpoints stay unaudited, and should. An observation is
    # recorded when it EXPOSES CUSTOMER MATERIAL or is a BULK EXTRACTION:
    #
    #   - a secret's receipt, including the owner's full email
    #   - an account-diagnostics bundle (auth log tail + sessions)
    #   - session inspection: one session's decrypted read-out, one customer's
    #     sessions, and the global session console (whose rows carry email, IP
    #     and user agent, and whose search is a free-text index over customer
    #     addresses)
    #   - the audit trail itself, on all three of its readers — reading the
    #     flight recorder is itself an operator action worth recording
    #   - the 365-day usage export
    #
    # Reading the site banner, the billing catalog, feature flags or a config
    # read-out exposes nothing about a customer and stays unaudited. The test is
    # the material, not the HTTP verb.
    #
    # It also holds DRY-RUN PREVIEWS (#4337): an op invoked with dry_run mutates
    # nothing, so it is an observation — but it is reconnaissance, enumerating
    # exactly what a destructive run would touch, and several of these default
    # to dry_run=true from the console. Previews are recorded with
    # `result: 'preview'`.
    #
    # WHY A THIRD COLLECTION rather than more room in `events`: the same
    # WRITE-FREQUENCY INVARIANT reasoning that split off `security_events`, one
    # step further. There the writer was untrusted; here it is trusted but
    # CHATTY BY CONSTRUCTION — an operator working one incident can page the
    # audit log, inspect a dozen sessions and re-run a preview a dozen times in
    # an afternoon, all without changing anything. On a count-capped set that is
    # an eviction pressure on the mutation trail even with nobody acting in bad
    # faith. Separate budgets remove the question: no volume of observation can
    # evict a single purge, role change or suppression, because the two sets are
    # trimmed independently.
    #
    # ON THE NAME: ADR-021 Decision 1 reserves "access log" for the
    # request/resource-focused sense and gives it to Secret Activity, and
    # Decision 5 reserves the `SecurityEvent` prefix for #2799. Neither is
    # infringed here for the same reason `security_events` does not infringe the
    # second: this is a SUB-COLLECTION of the operator stream, which already
    # owns the `ColonelAudit` prefix (its Redis key is
    # `colonel_audit_event:access_events`), not a new product surface. It is
    # never rendered outside the colonel app.
    class_sorted_set :access_events

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
    #
    #   4. A verb that OBSERVES without mutating — a curated sensitive read, or
    #      a dry-run preview — goes to `access_events` via {.record_access},
    #      under MAX_ACCESS_EVENTS + ACCESS_EVENT_RETENTION (#4335). Authorized,
    #      but chatty by construction; see that collection's note.
    #
    # All THREE trails are merged newest-first for reading by
    # {Onetime::ColonelAuditReader}, so the splits cost no queryability. The
    # projection tags each row with the trail it came from, because retention
    # differs per trail and "nothing before date X" means different things in
    # each.
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

    # Retention cap (by count) for the OBSERVATION trail (#4335).
    #
    # HALF the operator cap, deliberately. Not a guess at volume — a statement
    # of relative worth under a fixed memory budget. "Who changed what" is the
    # accountability record and gets the larger share; "who looked at what" is
    # supporting context for it. Sized so an operator's own working history
    # survives a normal review cycle (a busy incident is tens to low hundreds of
    # observations, so 5k is weeks of real use), while staying small enough that
    # the two trails together remain a predictable Valkey bound.
    #
    # Raising this is cheap and safe in a way that raising MAX_EVENTS is not:
    # the budgets are independent, so a bigger observation trail cannot cost the
    # mutation trail a single record.
    MAX_ACCESS_EVENTS = 5_000

    # Age bound (seconds) for the OBSERVATION trail, trimmed by score on every
    # access write — the same ZREMRANGEBYSCORE pass {SECURITY_EVENT_RETENTION}
    # gets, and for the same reason: observations go stale.
    #
    # Longer than the security trail's 7 days, shorter than the operator
    # trail's "no TTL at all", and both gaps are the point. Anonymous telemetry
    # is detection signal with a short useful life. An observation is an
    # ATTRIBUTED operator action, so it is reviewable evidence — "who was
    # looking at this account before it was drained" is a question asked days or
    # weeks later, which is what 30 days covers. It still expires, because
    # unlike a mutation an observation left no other mark in the system to
    # correlate against, and an indefinite record of everything an operator ever
    # looked at is itself surveillance data worth aging out.
    ACCESS_EVENT_RETENTION = 30 * 24 * 60 * 60 # 30 days

    # Placeholder written in place of any redacted value.
    REDACTED = '[REDACTED]'

    # --- The sink (#4334) ---------------------------------------------------

    # SemanticLogger category for the event-time sink. Its own name, not one of
    # the app categories in etc/defaults/logging.defaults.yaml, so an operator
    # can route or ship the audit stream independently of application logging —
    # a syslog appender filtered to this exact name, a log-collector rule on
    # stdout, or both. Matches the `ColonelAudit` code prefix ADR-021
    # Decision 5 assigns to the operator stream.
    SINK_LOGGER_NAME = 'ColonelAudit'

    # Level the sink emits at, PINNED rather than read from the logging config.
    # The default application level is `warn`; the audit sink is the durability
    # story, so it must not be silenceable by a generic level change or by an
    # operator turning the app quiet. Turning the sink OFF is a routing
    # decision (drop the category at the collector), not a level.
    SINK_LEVEL = :info

    # Log message every audit line carries, so a collector can match on it
    # without parsing the payload.
    SINK_MESSAGE = 'colonel.audit'

    # The verb constants that live on the model instead of on an emitter — this
    # one and its failed counterpart below (#4339).
    #
    # Nearly every verb has exactly one emitter, which owns its own AUDIT_VERB.
    # Colonel session establishment has TWO, one per auth mode — full mode syncs
    # the session in Auth::Operations::SyncSession, simple mode never loads the
    # auth app at all and establishes it in
    # Core::Logic::Authentication::AuthenticateSession. Neither can reference the
    # other's constant, and the string must be identical in both (the admin
    # console filters on it), so it is single-sourced here.
    #
    # The RULE this illustrates is "a multi-emitter verb is single-sourced on
    # whatever its emitters already share." For this one that is the model,
    # because an auth op and a core logic class share nothing else. The
    # audit-READ verbs (#4335) have three emitters — the list endpoint, the
    # export endpoint and the CLI — which already share
    # {Onetime::ColonelAuditReader}, so they are single-sourced there instead.
    # This model knows nothing about reading surfaces and should not start.
    VERB_COLONEL_SIGNIN = 'colonel.signin'

    # The FAILED counterpart (#4339). Same two-emitter shape as the verb above,
    # so by the same rule it gets the same home: full mode emits from the
    # Rodauth login-failure hook (Auth::Config::Hooks::Login), simple mode from
    # the failure funnel in Core::Logic::Authentication::AuthenticateSession,
    # and neither can reference the other. The two sites also share
    # {Onetime::ColonelSigninFailure}, which owns the emit-if-colonel guard —
    # but the CONSTANT stays here, because what has to be identical in both
    # places is the string the console filters on, and that is this model's
    # concern rather than a guard helper's.
    #
    # AN UNDERSCORE, NOT A THIRD DOT, and the reader's filter is the reason.
    # {Onetime::ColonelAuditReader} matches a verb EXACTLY or as a DOTTED
    # CATEGORY PREFIX (`stored.start_with?("#{verb}.")`), so a
    # `colonel.signin.failed` spelling would make the EXISTING `colonel.signin`
    # filter start returning failures as well. That filter is how an operator
    # asks "who signed in", and its answer must not silently widen to "who
    # tried". Spelled with an underscore the two are siblings:
    # `colonel.signin` returns sign-ins, `colonel.signin_failed` returns
    # attempts, and `colonel` still rolls both up when that is what is wanted.
    # It also matches the house verb style, where a qualifier is an underscore
    # inside a segment (`customer.set_role`, `session.revoke_all`).
    #
    # Keeping them separately filterable matters more here than it would for
    # most verb pairs, because the two do not even live in the same collection:
    # a success is authenticated operator activity and goes to `events`, while
    # a failure is reachable by an unauthenticated caller and goes to
    # `security_events` via {.record_security}. Their retention differs (no TTL
    # vs 1k/7 days), so one filter spanning both would return rows whose
    # ABSENCE means two different things.
    VERB_COLONEL_SIGNIN_FAILED = 'colonel.signin_failed'

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
      # Best-effort by DEFAULT: a failed audit write must never break the
      # operation that called it, so any error is logged and swallowed (returns
      # nil). Destructive verbs opt out with `fail_closed: true` — see the
      # fail-closed contract in the class docs and the rescue below.
      #
      # @param actor [String, #extid, #email] the acting colonel's PUBLIC identity
      #   (extid or email). Never pass an internal objid. A Customer-like object is
      #   accepted and its extid/email is extracted.
      # @param verb [String, Symbol] the operation name, e.g. 'customer.set_role'.
      # @param target [String, Symbol] the PUBLIC id of the affected resource.
      # @param result [String, Symbol] outcome, e.g. :success / :failure.
      # @param detail [Hash, String, nil] optional minimal context. Redacted before
      #   storage; never include secret content, tokens, or passphrases.
      # @param fail_closed [Boolean] when true, a write failure raises
      #   {Onetime::AuditWriteFailure} instead of returning nil. For DESTRUCTIVE
      #   verbs only (purge / delete / role / revoke / suspend): it surfaces the
      #   missing trail to the operator, it does NOT roll the mutation back.
      # @return [Hash, nil] the stored event (string keys), or nil if the write
      #   failed and `fail_closed` is false.
      # @raise [Onetime::AuditWriteFailure] when the write fails and
      #   `fail_closed` is true.
      def record(actor:, verb:, target:, result:, detail: nil, fail_closed: false)
        event = build_event(actor: actor, verb: verb, target: target, result: result, detail: detail)

        # SINK FIRST (#4334), then the cache. Everything below this line can
        # fail — Valkey down, key evicted, trim racing — without losing the
        # record, because the line has already left the process. Reversing the
        # order would put the durable copy behind the fragile one.
        emit_to_sink(event, :events)

        events.add(event, event['created'])
        trim!
        event
      rescue StandardError => ex
        # The log line is written on BOTH paths, before the branch: an operator
        # reading logs sees the same record-failed line whether the caller
        # aborted or carried on, and the raise below carries the original
        # exception as its `cause`.
        log_record_failure(ex, verb, target, result)

        # FAIL-CLOSED (#4333) — the contract the epic-D4 HOOK deferred.
        #
        # Which verbs opt in: the destructive family named by the issue —
        # customer.purge, organization.delete, customer.set_role,
        # customer.suspend/unsuspend, session.delete / .revoke / .revoke_all,
        # secret.delete, queue.dlq.purge — plus the direct peers of those verbs
        # that destroy or revoke by the same standard (domain.remove,
        # membership.remove, membership.set_role). What they share is that a
        # completed action leaves no other durable evidence: reconstructing it
        # afterwards means asking the operator what they did.
        #
        # Which verbs deliberately do NOT: everything additive or corrective
        # (create, add, repair, reconcile, verify, banner, plan/entitlement
        # changes, email tooling). Their effects are inspectable in the records
        # they leave behind, so trading a working operation for a hard failure
        # buys nothing.
        #
        # And REFUSAL records stay fail-open even inside a fail-closed op
        # (Memberships::Remove#record_refusal, Memberships::SetRole): a refusal
        # mutated nothing, so aborting it would turn a clean "no" into a 500.
        #
        # Honest scope: nearly every caller records AFTER its mutation, so this
        # aborts the RESPONSE, not the action. It converts "destroyed, reported
        # success, no trail" into "destroyed, reported failure, named verb and
        # target" — a signal an operator can act on.
        raise AuditWriteFailure.new(verb: verb, target: target) if fail_closed

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
      # ALWAYS best-effort — and unlike {.record} there is no `fail_closed`
      # keyword to opt out of it. Every writer here is reachable by an
      # unauthenticated caller, so an abort-on-write-failure mode would be an
      # abort primitive over whatever code path emitted the telemetry: trip the
      # audit write, take the surrounding request down with it. Errors are
      # logged and swallowed, unconditionally.
      #
      # @return [Hash, nil] the stored event (string keys), or nil if it failed.
      def record_security(actor:, verb:, target:, result:, detail: nil)
        event = build_event(actor: actor, verb: verb, target: target, result: result, detail: detail)

        # Same sink-then-cache ordering as {.record}, on the same logger under a
        # different `trail` field. Both trails are shipped: the split exists to
        # protect the operator trail's Redis budget, and the sink has no budget
        # to protect.
        emit_to_sink(event, :security_events)

        security_events.add(event, event['created'])
        trim_security!
        event
      rescue StandardError => ex
        log_record_failure(ex, verb, target, result)
        nil
      end

      # Record one OBSERVATION event: same shape as {.record}, stored in the
      # separate `access_events` collection with its own count cap and age
      # bound (#4335).
      #
      # Use this — never {.record} — for an authenticated colonel action that
      # MUTATES NOTHING: a curated sensitive read (see the collection's curation
      # principle) or a dry-run preview. The separation is the control described
      # in the WRITE-FREQUENCY INVARIANT: observation is chatty by construction,
      # so giving it its own budget means a busy afternoon in the console can
      # never cost the mutation trail a record.
      #
      # ALWAYS best-effort, and — like {.record_security} — with NO `fail_closed`
      # keyword to opt out of it. The reasoning differs from the security trail's
      # but lands in the same place: OBSERVING MUST NEVER BREAK THE CONSOLE. A
      # colonel opening a receipt or previewing a delete has changed nothing, so
      # there is no destroyed-with-no-trail scenario for fail-closed to surface;
      # all it could do is turn a broken audit write into a broken read-out,
      # taking the console down at exactly the moment an operator is trying to
      # understand something. The event is already in the sink either way.
      #
      # @param result [String, Symbol] outcome. `:success` for a read that
      #   answered; `'preview'` for a dry-run (see #4337).
      # @return [Hash, nil] the stored event (string keys), or nil if it failed.
      def record_access(actor:, verb:, target:, result:, detail: nil)
        event = build_event(actor: actor, verb: verb, target: target, result: result, detail: detail)

        # Same sink-then-cache ordering as the other two, on the same logger
        # under its own `trail` field. The sink has no budget to protect, so
        # nothing about the split changes what ships.
        emit_to_sink(event, :access_events)

        access_events.add(event, event['created'])
        trim_access!
        event
      rescue StandardError => ex
        log_record_failure(ex, verb, target, result)
        nil
      end

      # The sink handle: a dedicated SemanticLogger instance for
      # {SINK_LOGGER_NAME}, pinned to {SINK_LEVEL}.
      #
      # Its own instance rather than one of the boot-cached app loggers
      # (Onetime.get_logger), because the level must NOT follow the application
      # logging config — see {SINK_LEVEL}. `SemanticLogger[]` returns a fresh
      # instance per call, so setting a level here changes nothing for any other
      # logger of any name; the appenders route by name regardless.
      #
      # Public so an operator (or a test) can reach the same instance the write
      # path uses.
      #
      # @return [SemanticLogger::Logger]
      def sink_logger
        @sink_logger ||= SemanticLogger[SINK_LOGGER_NAME].tap { |logger| logger.level = SINK_LEVEL }
      end

      # Newest-first slice of the audit trail. Backs the admin audit view
      # (GET /api/colonel/audit via ColonelAPI::Logic::Colonel::ListColonelAuditEvents).
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

      # Newest-first slice of the OBSERVATION trail. Same contract as
      # {.recent}, over the separate collection.
      #
      # @param limit [Integer] max events to return (most recent first).
      # @param offset [Integer] rank offset into the newest-first ordering.
      # @return [Array<Hash>] events with string keys, newest first.
      def recent_access(limit = 100, offset = 0)
        limit  = limit.to_i
        offset = offset.to_i
        return [] if limit <= 0

        offset = 0 if offset.negative?
        access_events.revrange(offset, offset + limit - 1)
      end

      # @return [Integer] number of retained events.
      def count
        events.element_count
      end

      # @return [Integer] number of retained security-telemetry events.
      def security_count
        security_events.element_count
      end

      # @return [Integer] number of retained observation events.
      def access_count
        access_events.element_count
      end

      # Enforce the count cap: keep only the newest `cap` events, dropping the
      # oldest overflow. Runs on every write; also callable directly.
      #
      # Members are scored by creation time (ascending), so the newest sit at the
      # highest ranks. Removing ranks 0..-(cap+1) drops everything but the last
      # `cap`. When count <= cap this is a no-op (Redis removes nothing).
      #
      # TAMPER RESISTANCE (#4334): `cap` is CLAMPED UP to MAX_EVENTS. This method
      # is public and its argument used to be taken at face value, which made
      # `trim!(0)` a one-call wipe of the entire operator trail — a destructive
      # primitive sitting on the audit API, reachable by any code that could
      # reach the class. Retention now only ever widens here; narrowing it is a
      # change to MAX_EVENTS, i.e. a code change under review. Callers that
      # legitimately want a smaller trail are asking for a different constant,
      # not a different argument.
      #
      # @param cap [Integer] requested retention; values below MAX_EVENTS are
      #   raised to MAX_EVENTS.
      # @return [Integer] number of events removed.
      def trim!(cap = MAX_EVENTS)
        cap = [cap.to_i, MAX_EVENTS].max

        events.remrangebyrank(0, -(cap + 1))
      end

      # Enforce BOTH bounds on the security-telemetry trail: the count cap (as
      # {.trim!}) and the age bound, which is applied by score because sorted-set
      # members cannot carry an individual TTL. Runs on every security write.
      #
      # BOTH arguments are clamped in the widening direction, for the reason
      # given on {.trim!}: `cap` is raised to MAX_SECURITY_EVENTS, and a POSITIVE
      # `max_age` below SECURITY_EVENT_RETENTION is raised to it — otherwise
      # `trim_security!(cap, 1)` would be the same wipe primitive by the age
      # door. A non-positive `max_age` still disables the age pass entirely,
      # which keeps MORE data and is therefore not a way around the invariant.
      #
      # @param cap [Integer] requested retention; raised to MAX_SECURITY_EVENTS
      #   when smaller.
      # @param max_age [Integer] seconds; events older than this are dropped.
      #   Non-positive disables the age bound (the count cap still applies);
      #   a positive value below SECURITY_EVENT_RETENTION is raised to it.
      # @return [Integer] number of events removed by both passes.
      def trim_security!(cap = MAX_SECURITY_EVENTS, max_age = SECURITY_EVENT_RETENTION)
        cap = [cap.to_i, MAX_SECURITY_EVENTS].max

        removed = security_events.remrangebyrank(0, -(cap + 1)).to_i

        max_age = max_age.to_i
        return removed unless max_age.positive?

        max_age = [max_age, SECURITY_EVENT_RETENTION].max

        # Scores are creation times, so everything scored at or below the cutoff
        # is older than the retention window. Starting at 0 rather than '-inf' is
        # safe: every score this model writes is an epoch time.
        removed + security_events.remrangebyscore(0, Familia.now - max_age).to_i
      end

      # Enforce BOTH bounds on the OBSERVATION trail — count cap and age bound —
      # exactly as {.trim_security!} does for the security trail, including the
      # widening-only clamps. Runs on every access write.
      #
      # Same tamper-resistance contract (#4334): `cap` is raised to
      # MAX_ACCESS_EVENTS, a POSITIVE `max_age` below ACCESS_EVENT_RETENTION is
      # raised to it, and a non-positive `max_age` disables the age pass (which
      # keeps MORE data, so it is not a way around the invariant). Narrowing
      # observation retention means editing the constants — a code change under
      # review, not an argument a caller can pass.
      #
      # @param cap [Integer] requested retention; raised to MAX_ACCESS_EVENTS
      #   when smaller.
      # @param max_age [Integer] seconds; events older than this are dropped.
      #   Non-positive disables the age bound; a positive value below
      #   ACCESS_EVENT_RETENTION is raised to it.
      # @return [Integer] number of events removed by both passes.
      def trim_access!(cap = MAX_ACCESS_EVENTS, max_age = ACCESS_EVENT_RETENTION)
        cap = [cap.to_i, MAX_ACCESS_EVENTS].max

        removed = access_events.remrangebyrank(0, -(cap + 1)).to_i

        max_age = max_age.to_i
        return removed unless max_age.positive?

        max_age = [max_age, ACCESS_EVENT_RETENTION].max

        removed + access_events.remrangebyscore(0, Familia.now - max_age).to_i
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

      # Emit one already-redacted, already-built event to the sink (#4334).
      #
      # INDEPENDENT AND FAIL-OPEN, in both directions. This runs before the
      # datastore write, so a failure here must not stop that write — hence its
      # own rescue rather than falling through to {.record}'s, which would
      # abandon the Redis copy (and, for a fail-closed verb, abort the operation
      # over a broken log appender). Conversely a datastore failure afterwards
      # cannot un-emit what this already wrote, which is the whole point of the
      # ordering.
      #
      # The payload is the stored member verbatim plus `trail`, so a line in the
      # sink and a row in the console are the same record. It has already been
      # through {redact}, so nothing reaches the sink that would not reach Redis.
      #
      # @param event [Hash] the built event (string keys).
      # @param trail [Symbol] :events, :security_events or :access_events.
      # @return [Boolean] whether the line was emitted.
      def emit_to_sink(event, trail)
        sink_logger.public_send(SINK_LEVEL, SINK_MESSAGE, event.merge('trail' => trail.to_s))
        true
      rescue StandardError => ex
        OT.le(
          '[ColonelAuditEvent] sink emit failed',
          exception: ex,
          verb: event['verb'].to_s,
          target: event['target'].to_s,
          trail: trail.to_s,
        )
        false
      end

      def log_record_failure(ex, verb, target, result)
        OT.le(
          '[ColonelAuditEvent] record failed',
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
