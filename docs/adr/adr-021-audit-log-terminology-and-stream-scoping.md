---
id: "021"
status: proposed
title: "ADR-021: Audit Log Terminology & Event-Stream Scoping"
---

## Status

Proposed

## Date

2026-07-08

<!--
Owner:  ops@solutious.com
Affects: #2799 (security events), #3633 / #3635 / #3637 (secret-access events)
Shared surface: `audit_logs` entitlement, `multi_team_v1` plan gate
-->

## Context

Two independently-scoped tickets both describe "audit log" functionality, and until now
they had not been cross-linked or reconciled. They are **not duplicates** — they log
different things, from different sources, with different retention and actor semantics —
but they share one entitlement and will land in the same workspace surface, so the
terminology and visibility rules need to be settled before either frontend ships.

| | #2799 | #3633 / #3635 / #3637 |
|---|---|---|
| **What it logs** | Auth / account / SSO security events (login, MFA, password change, SSO config change) | Secret lifecycle & access events (created, secret_get, revealed, burned, expired, orphaned…) |
| **Source** | Rodauth SQL (`account_authentication_audit_logs`) + proposed Familia `AuditEvent` | Familia `AuditTrail` (Redis sorted set; since renamed `SecretActivity` — Decision 5) |
| **Actor attribution** | Yes (actor id, email, IP, UA) | No (recipients are anonymous capability-token holders) |
| **Retention** | TTL-based (90 days proposed) | Cap-based (newest 10,000 events per org) |
| **Status** | Unstarted | Backend shipped (#3635); UX in #3637 |

> **Status note (2026-08-02):** the context table above predates #3639/#3637.
> Secret Activity now DOES record actor attribution at capture time
> (`creator | authenticated_other | anonymous | system | unknown`, with
> `actor_id` as the full customer objid, identity resolved at read time) —
> see `docs/architecture/audit-logging.md` and ADR-023. The terminology and
> scoping decisions below are unaffected; Decision 1's "Actor?: No" for #3635
> described the pre-#3639 state.

## Decision

### Decision 1 — Distinct names for the two streams

"Audit log" is retained only as the **feature / entitlement** label (`audit_logs`). The two
underlying streams get distinct, user-facing names so nobody expects actor attribution on
the secret stream or lifecycle semantics on the security stream.

| Ticket | User-facing name | Answers | Actor? | Store / retention |
|---|---|---|---|---|
| #2799 | **Security Events** (audit log, strict sense) | who did what to the account/org | Yes | SQL / TTL |
| #3635 | **Secret Activity** (access / usage log) | what happened to a secret | No | Redis / cap |

Rationale: this matches industry usage (NIST, Datadog, Huntress, 1Password) — "audit log"
is the accountability-focused, actor-attributed record; "access/activity log" is the
request-/resource-focused record. #2799 is the former; #3635 is the latter.

### Decision 2 — Separate stores, correlatable presentation

Keep the two streams in separate backends (different sources, schemas, retention, and
actor models — unifying the stores has no benefit). Standards do not require a single
store. The market expectation applies at the **consumption layer**: events should share a
consistent timeline, timestamp format, and export path so a reviewer can line them up
(e.g. "around the time SSO config changed, what secrets were accessed?").

Presentation direction: **two labeled tabs/filters** ("Security Events" vs "Secret
Activity") feeding one correlatable view — not a forced backend merge. The Redis-vs-SQL and
cap-vs-TTL differences are a UI-layer concern only.

### Decision 3 — Compliance framing

- #2799 (Security Events) is the **compliance artifact**. SOC 2 expects authentication
  events (success **and** failure), access/permission changes, config changes, and
  sensitive-data access, typically retained **≥12 months**. The proposed 90-day TTL likely
  undersells this — revisit retention if this stream is marketed as a compliance audit log.
- #3635 (Secret Activity) is **product telemetry**, not a compliance record. The 10k-event
  cap and lack of actor attribution are fine for "was my secret seen?" but must not sit
  under copy that implies forensic accountability. (#3637 already flags the missing
  custid/IP/UA — keep the naming distinct so copy doesn't over-promise.)

### Decision 4 — Visibility model for Security Events (individual vs org)

Model every security event with three attributes and derive visibility from them:

- **actor** — who performed it
- **subject / target** — who it was done to (often == actor; differs for admin-on-member actions)
- **org context** — which org the event occurred in

**Individual view** = events where the user is actor **or** subject. (So "admin reset Bob's
MFA" appears in both the admin's and Bob's views.)

**Org view** = every event whose org context is this org, **plus** org-level/system events
with no individual subject (SSO config change, SCIM provision/deprovision, service-account
actions). The org view is therefore a *superset-plus*, not a strict superset of individual
views.

#### What must NOT roll up into the org (individual sees; org shouldn't)

- **Events from other org contexts or the personal-account context.** If a login is a
  single global account used across multiple orgs, Org A must not see events that occurred
  while the user acted in Org B or personally. **Scope every event to the org it occurred
  in** — the org view is not "everything about this human." *(Primary correctness risk.)*
- **Fine-grained location/device data, jurisdiction-dependent.** IP, geolocation, and
  device fingerprint are personal data. Exposing every member's raw IP/location org-wide
  can cross into regulated employee-monitoring (GDPR proportionality; works-council rules
  in DE/FR). Auth events are legitimate-interest loggable; the concern is granularity.
  Consider coarsening at the org tier (city-level, or a "new device" boolean). **Confirm
  with counsel before exposing raw IP/UA org-wide.**

#### What must NOT appear in the individual view (org/admin only)

- **Detection internals** — risk scores, "session flagged suspicious," anomaly-rule matches
  (exposing detection logic aids evasion by a compromised/insider account).
- **Active-investigation meta-events** — e.g. "admin viewed your security log" (decide
  deliberately whether to suppress from the subject).
- Other members' events (the individual view is strictly self-scoped).

#### What must NOT appear in either, at this layer

Raw credentials, session tokens, TOTP/MFA secrets, full unobscured emails (keep
`obscure_email` consistent across both tiers).

#### Explicit asymmetry

Failed logins and MFA failures appear in **both** views — the individual needs them
("someone is trying to get into my account"); the org needs them for brute-force /
credential-stuffing detection. Do not treat failures as admin-only.

### Decision 5 — Code identifier naming (#3977)

Added 2026-08-03, when #3977 aligned code identifiers with Decision 1's stream
names. This table is the authority for stream prefixes; code touching a stream
uses its prefix. Bare "audit" is reserved for the strict, actor-attributed
accountability sense (per Decision 1's rationale) — it appears only in the
operator stream and in the shared feature/entitlement label.

| Stream | User-facing name | Code prefix | Key identifiers |
|---|---|---|---|
| Secret Activity | Secret Activity | `SecretActivity` | `Organization::Features::SecretActivity`, `ListSecretActivity`, `useSecretActivity`, `secret-activity.ts` |
| Operator audit log | Operations Ledger | `ColonelAudit` | `ColonelAuditEvent`, `ListColonelAuditEvents`, `ColonelAuditLog.vue`, `colonel-audit.ts` |
| Security Events | Security Events | `SecurityEvent` | **Reserved for #2799** — do not use for anything else |
| Config-change loggers | — (log lines only) | `ConfigChangeLogger` | `ConfigChangeLogger`, per-config `ChangeLogger` modules |

Intentionally unchanged by #3977: the `audit_logs` entitlement label (Decision 1
retains "audit log" as the feature/entitlement name) and Rodauth's
`account_authentication_audit_logs` table (upstream schema).

> **Status note (2026-09-01, #4335):** the Operations Ledger row is now backed
> by **three** separately-capped Familia collections behind one `ColonelAudit`
> prefix — `events` (operator mutations), `security_events` (telemetry an
> unauthenticated caller can cause) and `access_events` (authenticated
> observations: curated sensitive reads and dry-run previews). They are a
> STORAGE control, not new streams in this ADR's sense: one prefix, one
> console, one export, merged on read and tagged with a `trail` field. Nothing
> in Decisions 1–5 changes.
>
> Two names deserve an explicit note. `access_events` does **not** claim
> Decision 1's "access/activity log" label — that stays with Secret Activity;
> this is an internal sub-collection of the operator stream, never a
> user-facing surface. `security_events` likewise predates and does not claim
> the `SecurityEvent` prefix Decision 5 reserves for #2799. Both are named for
> what they hold inside a stream that already owns its prefix. See
> `docs/architecture/audit-logging.md` for the budgets and the curation
> principle.

## Scope of this record

This ADR settles **terminology, stream scoping, and the Security Events visibility model**.
It deliberately does **not** specify the Secret Activity network-capture privacy mechanics
(partial IP, partial user agent, keyed correlation hash) — that is a separate decision with
a different owner (privacy/legal) and a different review lifecycle, recorded in
**ADR-022 (Secret Activity network-capture privacy stance, #3640)**. Open item 2 below
(counsel review of org-tier IP/geo/device granularity for Security Events) is tracked here
because it concerns the #2799 stream; ADR-022 governs the #3640 stream.

## Open Questions

1. Retention target for Security Events if positioned as compliance (≥12 months?).
2. Legal review of org-tier granularity for IP / geolocation / device data.
   **Still open. Blocking a shipped surface (2026-08-16):** #3989 implemented
   org-tier country capture on the Secret Activity stream (`net_country`, an
   ISO-3166-1 alpha-2 code; see ADR-022 Implementation Notes). It shipped
   **default-OFF** behind `features.secret_activity.geo_country_enabled`
   specifically because this question is unanswered. The flag must not be
   enabled until counsel signs off here and ADR-022 is amended to record that
   sign-off. Note the scope difference: this question was raised for the #2799
   Security Events stream, but the same org-tier geo-exposure concern is what
   gates #3989 on the #3635 stream, so answering it needs to cover both.
3. #3637's open UX questions (merge `status_get`/`secret_get`; surface vs hide `previewed`).
4. Whether personal-account mutations (email/password change) surface to every org a
   multi-org user belongs to, or only the org owning the identity.

## References

- SOC 2 audit log requirements — AuditKit, AuditPath
- NIST CSRC audit-log glossary; Datadog "What is Audit Logging"; Huntress access-vs-audit logs
- SIEM data normalization (SearchInform); NIST SP 800-92
- Vendor patterns — 1Password Events API, Doppler security fact sheet
- ADR-022 — Secret Activity network-capture privacy stance (#3640)
- ADR-023 — Audit actor attribution accuracy (refines Decision 4: what to record
  when the actor is unresolved)
