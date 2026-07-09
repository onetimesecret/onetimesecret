---
id: "023"
status: proposed
title: "ADR-023: Audit Actor Attribution Accuracy — Never Fabricate an Actor"
---

## Status

Proposed

## Date

2026-07-09

<!--
Owner:  ops@solutious.com
Affects: #2799 (Security Events actor), #3639 (Secret Activity lifecycle actor)
Refines: ADR-021 Decision 4 (actor / subject / org model)
-->

## Context

Adding actor identity to Secret Activity lifecycle events (#3639) surfaced a
small but revealing question. The actor discriminator — `creator` /
`authenticated_other` / `anonymous` — is computed from the acting customer and
the secret being consumed. On one defensive branch the secret is absent
(`target_secret` nil): the caller is authenticated, but we cannot establish
their relationship to a secret we don't have. What actor do we record?

The change was first framed as a binary — default the nil case to
`authenticated_other` (its current behavior, since `nil&.owner? → false`) or to
`anonymous`. Researching how mature audit systems and data-protection law treat
an *unresolved* actor showed that **both options are wrong for the same reason**,
and that the lesson generalizes well beyond this one branch.

## Decision

**An audit event must never record a fabricated or guessed actor. Where the
actor — or its relationship to the subject — cannot be established, record an
explicit `unknown`; never a value that asserts a fact we cannot support.**

Four rules follow:

1. **No convenient default.** `authenticated_other` asserts "authenticated **and
   not the owner**" — the "not owner" half is unsubstantiated when there is no
   secret. `anonymous` asserts "**unauthenticated**" — outright false for an
   authenticated caller, and strictly worse, because it discards a fact we *do*
   know to assert one that is false. Neither is acceptable.
2. **Record what is known; mark the rest unknown.** Emit `actor: 'unknown'`
   while keeping the authenticated principal's shortid (`actor_id`) when we have
   one. The truthful statement is "an authenticated principal `<id>` acted;
   ownership indeterminate" — accurate and minimal.
3. **Separate "who acted" from "their relation to the subject."** Collapsing
   both into a single enum is what forced the false choice; `unknown` keeps the
   two dimensions honest.
4. **Alert, don't raise.** The indeterminate branch signals a programmer error,
   so it logs (`OT.le`) — but it never raises. Attribution is best-effort
   observability and must not break the consume path (#3633; CAS-gated reveal,
   ADR-019). Accuracy is fixed by the *value* recorded, not by changing control
   flow.

This governs **every** actor-attributed stream: Security Events (#2799) and the
Secret Activity lifecycle actor (#3639). It refines ADR-021 Decision 4, which
models each event as actor / subject / org but did not say what to record when
the actor is unresolved.

## Rationale

- **Accuracy is a legal obligation, not a nicety.** An actor attribution is
  personal data about an identifiable person, so GDPR Art. 5(1)(d) ("accurate
  and, where necessary, kept up to date") applies directly. A *false*
  attribution is a compliance defect, not a harmless default — the decisive
  argument against both `authenticated_other` and `anonymous` in the unresolved
  case. `unknown` is the accurate representation.
- **Data minimization aligns.** `unknown` + shortid stores the least identifying
  thing that still serves the purpose (Art. 5(1)(c); pseudonymization, Art. 4(5)
  / Recital 26) — consistent with the trail's existing shortids-only, masked-IP
  posture (ADR-022).
- **Never misattribute to the creator.** `unknown` satisfies the trail's
  standing "never assume the creator" guard (the anonymous-guest nil-objid
  precedent) without the collateral inaccuracy of `anonymous`.
- **The reference implementations agree.** Microsoft's Entra ID / Office 365 /
  Exchange audit logs record an explicit **`Unknown`** principal when the actor
  cannot be resolved, rather than guessing. Clerk **omits** the `act` (actor)
  claim entirely unless a real impersonator exists — presence recorded honestly,
  never defaulted. Typed actor schemas (`user` / `service` / `system`) treat
  "unresolved" as its own type, never a mislabeled user.

## Consequences

- Add `unknown` to the recognized lifecycle actors (`LIFECYCLE_ACTORS`) and have
  `lifecycle_actor_context` return `{ 'actor' => 'unknown', 'actor_id' => … }`
  on the nil-`target_secret` branch instead of `authenticated_other`
  (`apps/api/v2/logic/secrets/actor_attribution.rb`,
  `receipt/features/deprecated_fields.rb`). Today that branch logs and records
  `authenticated_other`; this ADR proposes `unknown`. It is genuinely a
  can't-happen path (all call sites pass a loaded secret), so this is
  correctness-of-principle on a defensive branch, not a live bug.
- Any future actor-attributed surface (Security Events #2799 included) adopts the
  same `unknown` sentinel + alert rather than inventing a stream-local default.
- Consumers / UI that render `actor` must handle `unknown` explicitly (show
  "unknown", not a blank or a misleading label).

## References

- GDPR — Art. 5(1)(d) accuracy; Art. 5(1)(c) data minimization; Art. 4(5) /
  Recital 26 pseudonymization; Art. 5(2) accountability; Art. 6(1)(f) legitimate
  interest (lawful basis for security logging).
- Microsoft — ["Unknown actors in audit reports" (Entra ID)](https://learn.microsoft.com/en-us/troubleshoot/entra/entra-id/governance/unknown-actors-in-audit-reports);
  [Office 365 "Unknown" principal in the audit log](https://michev.info/blog/post/2151/login-events-in-the-office-365-audit-log-for-the-unknown-principal);
  ["ActorInfoString … audit log accuracy" (Exchange Online)](https://techcommunity.microsoft.com/blog/microsoft-security-blog/introducing-actorinfostring-a-new-era-of-audit-log-accuracy-in-exchange-online/4408093).
- Clerk — [session-token `act` (actor) claim](https://clerk.com/docs/guides/sessions/session-tokens)
  (present only under impersonation); [user impersonation](https://clerk.com/docs/guides/users/impersonation)
  (impersonator and subject kept as distinct fields).
- General guidance — record what is known rather than fabricate
  ([LoginRadius](https://www.loginradius.com/blog/engineering/auditing-and-logging-ai-agent-activity),
  [Prefactor](https://prefactor.tech/blog/audit-trails-in-ci-cd-best-practices-for-ai-agents));
  typed actor schemas ([Sonar](https://www.sonarsource.com/resources/library/audit-logging/),
  [Infisical audit-log guide](https://medium.com/@tony.infisical/guide-to-building-audit-logs-for-application-software-b0083bb58604)).
- Internal — ADR-021 (actor / subject / org model; this refines Decision 4);
  ADR-022 (Secret Activity network-capture privacy; same shortids-only,
  minimized posture); ADR-019 (at-most-once reveal; CAS-gated, best-effort audit
  path); #3639 (Secret Activity actor identity); #2799 (Security Events).
