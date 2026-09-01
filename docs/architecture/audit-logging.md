# Audit Logging

How Onetime Secret records, retains, and presents accountability data. This
document uses the terminology settled in ADR-021: **"audit log" is only the
feature/entitlement label** (`audit_logs`); the underlying data is two distinct
event streams with different sources, actor semantics, and retention. A third,
operator-facing log exists outside the entitlement entirely.

| Stream | User-facing name | Answers | Store / retention | Status |
|---|---|---|---|---|
| Secret Activity (#3633/#3635/#3637) | **Secret Activity** | what happened to a secret, and who acted | Valkey/Redis sorted set, capped (10,000 newest per org) | Shipped |
| Security Events (#2799) | **Security Events** | who did what to the account/org (login, MFA, SSO config) | SQL (`account_authentication_audit_logs`), TTL-based | Backend table live (Rodauth); product surface unstarted |
| Operator audit log | — (colonel-only) | what operators did in the admin console | `ColonelAuditEvent` (Familia) | Shipped, colonel app only |

Do not conflate them. Per ADR-021, "audit log" in the strict, actor-attributed
compliance sense is Security Events; Secret Activity began as access/usage
telemetry and has since gained full actor attribution (see below) — but the two
remain separate stores with separate retention, deliberately (ADR-021
Decision 2: correlation happens at the presentation layer, never by merging
backends).

Code identifiers follow the stream names (#3977; authoritative table in ADR-021
Decision 5): Secret Activity uses the `SecretActivity` prefix, the operator log
uses `ColonelAudit*`, the `SecurityEvent` prefix is reserved for #2799, and the
per-domain config loggers are `ConfigChangeLogger` / `ChangeLogger` (log lines
only, not a stream). The `audit_logs` entitlement label and Rodauth's
`account_authentication_audit_logs` table are intentionally unchanged.

## Secret Activity

### Capture pipeline

Every event flows through one chokepoint on its way to the organization's
trail. Logic classes compute request-scoped facts (actor, network context) and
thread them down; the model layer validates and appends.

```
  Request layer (has cust / request context)          Model layer (no request context)
┌─────────────────────────────────────────┐
│ V2 secrets logic                        │
│  BaseSecretAction ─── 'created' ────────┼──┐
│  AccessTelemetry ── fetch kinds ────────┼──┤   ┌──────────────────────────────────────┐
│    (secret_get, status_get, previewed,  │  │   │ Receipt                              │
│     creator_status_get)                 │  │   │  Features::AccessTimeline            │
│  ShowReceipt (v1+v2) ─ receipt_viewed ──┼──┼──▶│                                      │
│  RevealSecret / BurnSecret /            │  │   │  record_access_event                 │
│   ShowSecret ── actor_context ──────────┼──┘   │   (per-receipt timeline,             │
│    │                                    │      │    cap 100, saturation guard)        │
│    ▼                                    │      │        │                             │
│  ActorAttribution                       │      │        ▼                             │
│   lifecycle_actor_context(secret)       │      │  record_org_secret_activity_event ◀── lifecycle
│   → {'actor' =>..., 'actor_id' =>objid} │      │   • normalize_actor_attrs            │   transitions
│  Security::RequestContext (ADR-022)     │      │     (CENTRALIZED validation)         │   (revealed!,
│   → net_ip_partial / net_ua_partial /   │      │   • forces receipt/secret            │   burned!,
│     net_ip_hash                         │      │     shortids after the splat         │   expired!,
└─────────────────────────────────────────┘      └────────────┬─────────────────────────┘   orphaned!)
                                                              ▼
                                                 ┌──────────────────────────────────────┐
                                                 │ Organization                         │
                                                 │  Features::SecretActivity            │
                                                 │  record_secret_activity_event        │
                                                 │  sorted set `secret_activity_events` │
                                                 │  (score = epoch s, member =          │
                                                 │   event hash; cap 10,000)            │
                                                 └──────────────────────────────────────┘
```

Key files:

- `lib/onetime/models/organization/features/secret_activity.rb` — the store
- `lib/onetime/models/receipt/features/access_timeline.rb` — the chokepoint
  (`record_org_secret_activity_event`, `normalize_actor_attrs`) and the
  per-receipt timeline
- `lib/onetime/models/receipt/features/deprecated_fields.rb` — lifecycle
  transitions (CAS-gated; the audit emit fires only in the won-CAS branch, so
  each transition records exactly once — ADR-019)
- `apps/api/v2/logic/secrets/actor_attribution.rb`,
  `access_telemetry.rb`, `base_secret_action.rb` — request-layer capture
- `apps/api/v1/logic/secrets/actor_attribution.rb` — the v1 sibling (reveal /
  burn thread the same actor context)
- `lib/onetime/security/request_context.rb` — network-context reduction
  (ADR-022)

### Event kinds (11)

| Kind | Emitted when | Actor |
|---|---|---|
| `created` | secret concealed/generated in org context | `creator` |
| `status_get` / `secret_get` | a third party fetched the status/secret link | tri-state |
| `previewed` | the creator opened their own secret link | tri-state (creator by construction, but **recorded**, never inferred) |
| `creator_status_get` | the creator checked their own secret's status | tri-state |
| `receipt_viewed` | the creator's receipt page loaded (once per receipt, atomic claim) | tri-state |
| `revealed` / `burned` | terminal lifecycle transition (CAS winner) | tri-state |
| `expired` / `orphaned` | system-detected transition, no acting individual | `system` |
| `reveal_failed_undecryptable` | reveal rolled back on undecryptable ciphertext | tri-state (threaded from the reveal) |

"Tri-state" is the computed discriminator (`creator` / `authenticated_other` /
`anonymous`). A fifth value, `unknown`, is the ADR-023 sentinel for an actor —
or an actor-subject relationship — that cannot be established (defensive
branches and the central validator's fail-safe); it never arises on a healthy
path and is id-carrying when an authenticated principal is known.

### Event record

Members of the org sorted set are plain string-keyed hashes:

```
kind, at (epoch float), nonce            — identity of the event
receipt, secret                          — SHORTIDS (see identifier policy below)
actor                                    — creator | authenticated_other | anonymous | system | unknown
actor_id                                 — FULL customer objid (authenticated actors only)
net_ip_partial, net_ua_partial,          — privacy-reduced network context (ADR-022;
net_ip_hash                                fetch events only)
```

### Actor model: recorded, not derived

The trail is a B2B compliance surface, so the stored event is the artifact.
Two rules follow (decided on #3637, with #3639):

1. **Actor is recorded at capture time on every kind.** The UI and exports
   must never derive an implied actor from event semantics (e.g. "`previewed`
   is creator-by-construction") — exported data must match what is rendered.
2. **`actor_id` is the full customer objid, never truncated.** NIST SP 800-53
   AU-3(f)/AU-10, PCI DSS 10.2.2 + Req 8, and the OWASP Logging Cheat Sheet
   all require the identifier to resolve uniquely to an individual; vendor
   practice (CloudTrail `principalId`, GitHub `actor_id`, GCP
   `principalEmail`) never truncates the actor. The repo's shortid convention
   does **not** transfer here: secret/receipt identifiers are shortened
   because the full identifier is a capability token (the identifier IS the
   link); a customer objid grants no access.

The two identifier conventions therefore coexist in one record: `receipt` /
`secret` stay shortids (capability-token policy), `actor_id` is full
(traceability policy). `normalize_actor_attrs` in
`Receipt#record_org_secret_activity_event` enforces the actor half centrally
for every event:

- unrecognized/missing actor fails safe to `unknown` with an error log
  (ADR-023: `anonymous` would assert "unauthenticated", a fact an actorless
  event cannot support; `unknown` never misattributes — the standing
  anonymous-guest `nil == nil` owner-check precedent). A valid `actor_id`
  riding along is kept: record what is known, mark the rest unknown;
- `anonymous` and `system` events never carry an `actor_id`;
- blank ids are dropped; ids containing `@` are dropped with an error log that
  never prints the value (an email must never enter the trail);
- no truncation.

Attribution itself (`lifecycle_actor_context`) runs the anonymous guard
*before* the ownership test, because `Secret#owner?` compares objids and an
anonymous caller (nil objid) fetching a guest-created secret (nil owner)
would otherwise match `nil == nil` and be misattributed as the creator.

### Identity resolution happens at read time

Email and display name **never enter the append-only trail** (GDPR
minimization: erasure requests never have to touch it, and a recorded email
would go stale). Instead, the read endpoint resolves identity per page:

- `ListSecretActivity` (`apps/api/organizations/logic/organizations/list_secret_activity.rb`,
  serving `GET /api/organizations/:extid/secret-activity`)
  collects the distinct `actor_id`s on the page and joins each through
  `OrganizationMembership.find_by_org_customer` — **active memberships only**,
  best-effort per actor (one bad record cannot fail the page).
- The response envelope carries the results as a side map, never by mutating
  events:

```
{ user_id, organization_id,
  records: [ <event>, ... ],            — verbatim trail events
  count, total,                         — page size / org-wide count (saturates at cap)
  details: { offset, limit,
             actors: { "<objid>": { email, extid }, ... } } }
```

- An objid absent from `actors` (removed member, out-of-org actor, legacy
  truncated id) renders in the UI as the bare objid — unresolved but unique,
  the same semantics as CloudTrail's deleted principals. There is **no
  backfill** of historical events (fabricating audit data), so pre-cutover
  8-char actor ids persist in old events and simply never resolve.

The frontend contract lives in
`src/schemas/api/organizations/responses/secret-activity.ts`; the pager in
`src/shared/composables/useSecretActivity.ts`.

### Retention and abuse bounds

Two caps, one TTL rule:

- **Per-receipt timeline**: newest 100 events (`ACCESS_EVENTS_MAX`); once a
  receipt's own timeline is saturated its *fetch* events stop fanning out to
  the org trail, so one hammered link (scanner, monitor) cannot evict every
  other receipt's history. Lifecycle transitions bypass the guard. The
  timeline key's TTL is clamped to its receipt's remaining TTL.
- **Org trail**: newest 10,000 events (`SECRET_ACTIVITY_MAX_EVENTS`), no TTL
  (organizations are permanent records). `receipt_viewed` is additionally
  bounded to once per receipt by an atomic claim (`claim_once!`), since the
  receipt page is not covered by the timeline saturation guard.
- Append is best-effort everywhere: the trail never drives behavior, and a
  failed append must never break a state transition or read path.

Per ADR-021 Decision 3, the cap (not a TTL) is the retention story: Secret
Activity is not marketed as a long-horizon forensic archive. A durable export
consuming the same fan-out point is the designated path if that changes.

### Presentation

One display surface: the **Activity tab** of Organization Settings
(`/org/:extid/activity` → `SecretActivityTable.vue`). The `audit_logs`
entitlement (admin/owner roles on plans that include it, enforced server-side
by `require_entitlement_in!`) gates the panel **content only** — the tab is
always visible; unentitled users see an inline upgrade notice, never a hidden
tab (the entitlement-gated-skeleton trap). The table mounts lazily per tab
open, so each visit fetches fresh — desirable for an audit view.

## Security Events

The strict-sense audit log (ADR-021 Decision 1): actor-attributed
account/auth/SSO events — login success **and** failure, MFA changes,
password changes, SSO config changes.

Current state:

- Rodauth writes `account_authentication_audit_logs` in the auth SQL database
  (full-auth mode). The first internal reader is the account-diagnose tooling
  (operations + CLI + colonel; #3944).
- The customer-facing product surface (#2799) is unstarted. When built, it
  follows ADR-021 Decision 4's visibility model: every event carries
  **actor / subject / org context**; the individual view is
  actor-or-subject-scoped; the org view is org-context-scoped plus
  subject-less org events — never "everything about this human" across orgs,
  and never detection internals in the individual view. Failed logins appear
  in **both** views.
- Retention is TTL-based; ADR-021 flags that a 90-day TTL undersells SOC 2
  expectations (≥12 months) if this stream is marketed as the compliance
  artifact — unresolved (ADR-021 open question 1).

## Operator audit log (colonel)

`ColonelAuditEvent` (formerly `AdminAuditEvent`; renamed in #3977) records
operator actions in the admin console and is rendered only by the colonel app
(`ColonelAuditLog.vue`). It sits outside the
`audit_logs` entitlement and outside ADR-021's two-stream model — it answers
"what did *our operators* do," not "what happened in a customer's org."
Mentioned here only to prevent the name collision.

### Write-failure posture (#4333)

`ColonelAuditEvent.record` is best-effort by default: a failed audit write is
logged and swallowed, because it must not break the operation that called it.
DESTRUCTIVE verbs opt out with `fail_closed: true` and raise
`Onetime::AuditWriteFailure` instead — customer purge, organization delete,
customer/membership role change, session delete/revoke/revoke-all, account
suspend/unsuspend, secret delete, DLQ purge, custom-domain remove, membership
remove. What they share: the action destroys or revokes the very records that
would otherwise evidence it.

Be precise about the guarantee. Almost every call site records *after* its
mutation, so failing closed does **not** roll anything back and does not
prevent the destruction — it refuses to report success. The operator gets a
hard failure naming the verb and target rather than a green response over an
empty trail. Prevention would require recording before mutating; nothing does
today.

`record_security` is fail-open always and has no opt-out keyword: its writers
are reachable by unauthenticated callers, and an abort-on-write-failure mode
there would be an abort primitive over whatever path emitted the telemetry.
Refusal records inside otherwise fail-closed ops (`Memberships::Remove`,
`Memberships::SetRole`) also stay fail-open — a refusal mutated nothing.

### Durability: the sink is the record, Valkey is the cache (#4334)

Every event goes to two places, **in this order**:

1. **The sink** — a structured log line on the dedicated `ColonelAudit`
   SemanticLogger category, emitted *before* the datastore write. Message
   `colonel.audit`, payload = the stored event plus `trail`
   (`events` / `security_events`). This is the durability story: it leaves the
   process immediately and nothing in the codebase can retract it.
2. **The cache** — the capped sorted sets. Recent, filterable, bounded; what
   the console, the export endpoint and the CLI query. Not an archive, and
   never sized to be one.

The ordering is the guarantee: a Valkey outage, an eviction or a trim cannot
lose the record. The two are independent in both directions — a sink failure is
caught and logged and never costs the Redis write or the caller; a datastore
failure never un-emits the sink line (which is what makes the fail-closed
posture above survivable: the operator is told the trail is broken, and the
event is still in the log stream).

By default the sink rides the console appender (stdout in server modes, stderr
under the CLI). An **optional syslog appender**, filtered to the `ColonelAudit`
category and **default off**, ships it separately — `audit.syslog` in
`etc/defaults/logging.defaults.yaml`, `LOG_AUDIT_SYSLOG=true` to enable, with
`LOG_AUDIT_SYSLOG_URL` / `_LEVEL` / `_FACILITY`. A local `syslog://` URL needs
no third-party gem; a remote `tcp://` / `udp://` URL needs `syslog_protocol`
(and `net_tcp_client` for TCP), which are not bundled — the appender is then
skipped with one boot warning and the stream still reaches stdout.

The sink's level is pinned in code (`SINK_LEVEL`), not read from the logging
config: the durability story must not go quiet because the application default
level was raised. Turning it off is a routing decision at the collector.

### Reading and exporting (#4334)

Three readers, one projection — `Onetime::ColonelAuditReader` (`lib/`, so the
CLI reaches it without an app autoloader) owns the merge of both trails, the
`actor` / `verb` filter semantics, and the **field allowlist**
(`id, actor, verb, target, result, detail, created`):

| Surface | Entry point | Body |
|---|---|---|
| Console list | `GET /api/colonel/audit` | JSON page + pagination |
| Console export | `GET /api/colonel/audit/export?format=csv\|ndjson` | `text/csv` / `application/x-ndjson` attachment |
| Shell | `bin/ots audit list [--limit] [--actor] [--verb] [--format text\|json\|csv\|ndjson]` | terminal table or a serialisation |

The export route is the one colonel route that is not `response=json`: Otto's
Logic-class handler never sees the Rack response and its JSON handler always
re-encodes the body, so the download uses the `Klass.method` route form
(precedent: `GET /ask Internal::ACME::AskHandler.call`). Because the body is not
JSON it has **no Zod schema** — documented in
`src/schemas/api/internal/responses/colonel-audit.ts`; the fields it serialises
are the same allowlist `colonelAuditEventSchema` already types. All three
surfaces are read-only (CONTRACT 4).

### Retention narrows only via the constants (#4334)

`trim!` and `trim_security!` are public and used to take their arguments at face
value, so `trim!(0)` was a one-call wipe of the operator trail — a destructive
primitive on the audit API. Both now **clamp in the widening direction**: a cap
below `MAX_EVENTS` / `MAX_SECURITY_EVENTS` is raised to it, and a positive
`max_age` below `SECURITY_EVENT_RETENTION` is raised to it (a non-positive
`max_age` still disables the age pass, which keeps *more*). Narrowing retention
is a change to the constants — a code change under review.

Stated honestly: this bounds the audit API, not the Familia collection behind
it. `ColonelAuditEvent.events.clear` still exists and is what test setup and
deliberate operator surgery use; no application code calls it, and the sink
above is untouched by anything done to Valkey.

## Cross-cutting rules

- **Never fabricate an actor** (ADR-023): where the actor or its relation to
  the subject cannot be established, record what is known and mark the rest —
  never a convenient default that asserts an unsupported fact. Attribution is
  best-effort observability: log the anomaly (`OT.le`), never raise into the
  consume path.
- **At-most-once emission** (ADR-019): lifecycle audit events fire only inside
  the won-CAS branch of their state transition; concurrent losers record
  nothing.
- **Privacy reduction at capture** (ADR-022): network context is stored only
  as partial IP (last IPv4 octet zeroed), stripped/truncated UA, and a keyed
  HMAC over the partial IP for correlation without disclosure. Raw IP / full
  UA are architecturally unavailable at the capture layer.
- **One authority per value** (ADR-027 spirit): actor validation lives in
  exactly one place (`normalize_actor_attrs`); identity resolution lives in
  exactly one place (`ListSecretActivity`); neither is duplicated per call site.

## Known divergences and open items

- ~~ADR-023's `unknown` actor is not yet in the recognized enum.~~ Resolved
  2026-08-02: ADR-023 ratified (Accepted). `unknown` is in
  `RECOGNIZED_ACTORS` (id-carrying), the nil-secret branch and the central
  validator's fail-safe both record it, and the frontend `KNOWN_ACTORS` +
  i18n label render it. Ratification also surfaced and fixed the v1
  reveal/burn paths, which threaded no actor context and recorded
  authenticated consumers as `anonymous` — see ADR-023's ratification note.
- ~~ADR-021's context table predates #3639/#3637.~~ Resolved 2026-08-02: a
  status note in ADR-021 marks the table's "Actor attribution: No" row as
  describing the pre-#3639 state; its terminology and scoping decisions
  stand.
- Security Events retention target and org-tier IP/geo granularity await
  counsel review (ADR-021 open questions 1–2).

## References

- ADR-019 — At-most-once secret reveal (CAS claims the audit emit rides on)
- ADR-021 — Audit log terminology & event-stream scoping
- ADR-022 — Secret Activity network-capture privacy stance
- ADR-023 — Audit actor attribution accuracy (never fabricate an actor)
- Issues: #2799 (Security Events), #3633/#3635/#3637 (Secret Activity),
  #3639 (lifecycle actor), #3640 (network context)
- Full-objid decision record:
  https://github.com/onetimesecret/onetimesecret/issues/3637#issuecomment-5156586408
