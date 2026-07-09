---
id: "020"
status: accepted
title: "ADR-020: Request-Scoped Entitlement Preview at the WithEntitlements Chokepoint"
---

## Status

Accepted

## Date

2026-07-07

## Context

Plan preview mode lets a colonel temporarily assume a target plan's entitlements to test functionality across plans. The storage design is sound: session-scoped Redis sets (`session:<id>:entitlement_preview_grants` / `_revokes`, written by `SetEntitlementPreview`) implementing reset-and-substitute over the org's materialized entitlements, cleared on logout, never touching billing state.

The application design is not. The override is applied only where a consumer explicitly opts in via `entitlements_for_request(session)` — and exactly one consumer does: the billing entitlements controller (`apps/web/billing/controllers/entitlements.rb`). Every other read path resolves entitlements preview-blind:

1. **Org API serialization** — `Organization#safe_dump` includes `entitlements: org.entitlements` (`organization/features/safe_dump_fields.rb:41`). `/api/organizations` list/get therefore serves actual-plan entitlements. The frontend org store is populated from this endpoint; any `fetchOrganizations()` clobbers preview-aware entitlements previously merged in by `PlanPreviewModal.syncPreviewState()`.
2. **Entitlement middleware** — `lib/middleware/entitlement_check.rb:62` calls `org.can?` with `env` in hand and ignores the session.
3. **Domain config policies** — `domain_config_authorization.rb:110`, `incoming_config/base.rb:67`, `put_homepage_config.rb:153`, `sender_config/base.rb:71`, `recipient_resolver.rb:135` all call `org.can?`.
4. **The banner** — `authentication_serializer.rb:46` reads `sess[:entitlement_preview_planid]` directly, a third source of truth.
5. **Membership entitlements (amended 2026-07-07)** — `OrganizationMembership#can?`/`#entitlements` (`organization_membership/features/with_materialized_entitlements.rb:169`) read the membership's *own* materialized set, never routing through `Organization#entitlements`. An org-side chokepoint alone does not reach them. Consumer: `get_permissions.rb:223-239` serves `can_view`/`can_edit`/`can_manage_settings` flags from `mem.can?` — those surfaces would keep showing the actual plan during preview. Worse, the coverage would be *inconsistent*: memberships never materialized fall back to `compute_entitlements_from_role` (line 227), which reads `org.entitlements` at request time and therefore **would** inherit the preview through the org chokepoint, while materialized memberships would not. Per-member divergence is the same symptom class this ADR exists to kill.

`can?` itself (`features/with_entitlements.rb:70`) never consults the session, so every guard built on it is blind by construction. Limits have a parallel one-off (`limit_for_request`, `with_materialized_limits.rb`) with the same opt-in polarity. (`EntitlementCheck` in item 2 is currently defined but mounted nowhere; it is listed because any future mount would default blind — the polarity problem includes consumers that don't exist yet.)

The observed failure mode follows directly: banner says "testing with Team Plus" (session state) while feature gates show the actual free plan (safe_dump state), and backend writes 403 even when the UI unlocks. Each fix to date has patched one consumer — the serializer carve-out ("entitlements intentionally NOT included", `organization_serializer.rb:55`), the modal's dual-refresh dance — while every new consumer defaults back to the blind path. The polarity guarantees regression.

## Decision

**Apply the session preview override once per request, inside `WithEntitlements#entitlements`, via a Fiber-scoped request context set by middleware.** Consumers become preview-aware by construction instead of by opt-in; the preview-blind path becomes unreachable during a preview.

**Mechanism.** A middleware (after session load) reads `entitlement_preview_grants_key` / `_revokes_key` / `_planid` from the session once and stashes them in a Fiber-local (`Fiber[:ots_entitlement_preview]`), cleared in `ensure`. This follows the existing request-local precedents (`connection_pinning.rb`, `logger_methods.rb`) and is safe under Puma's thread-per-request model. `WithEntitlements#entitlements` consults the context and, when present, returns `reconcile_with_session_overrides(grants_key, revokes_key)`. Everything downstream — `can?`, `safe_dump`, org API serialization, domain config policies, `EntitlementCheck` middleware, the banner serializer — inherits the override through the one method they already call. `WithMaterializedLimits#limit_for` consults the same context's `planid`, folding in the limits one-off.

**Second chokepoint: membership (amended 2026-07-07).** `OrganizationMembership#entitlements` consults the same Fiber-local. When preview is active it bypasses its materialized set and computes via `compute_entitlements_from_role` — `org.entitlements ∩ ROLE_ENTITLEMENTS[role]`, where the org side is now preview-aware through the first chokepoint. Two properties fall out: (a) materialized and non-materialized memberships behave identically during preview, closing the divergence described in Context item 5; (b) role-intersection semantics are preserved — preview simulates a different *plan*, never a different *role*, so a previewing colonel cannot observe entitlements their role template would mask (consistent with #3491's fusion-point rule). This is a second application point, not a return to opt-in: both chokepoints are `#entitlements` readers driven by one context, and no consumer above them changes.

**Scope semantics (deliberate).** The override applies to *any* Organization resolved during a request carrying the preview session — not only the colonel's default org. This matches current reconciler semantics and is correct for the feature's purpose (testing whatever the colonel is looking at). It is stated here so it is not rediscovered as a surprise.

**Security posture unchanged.** The write path remains colonel-only (`verify_one_of_roles!(colonel: true)`); the read path is inherently bound to the session that set it; materialized Redis state is never mutated, so nothing leaks to other members or survives session end.

**Alternatives rejected:**

| Alternative | Why rejected |
|---|---|
| Keep per-consumer opt-in (`entitlements_for_request`) | Demonstrated whack-a-mole; every new consumer defaults blind |
| Materialize preview into the org's Redis sets | Org-scoped state leaks to all members and sessions of the org; survives crashes; violates session-scoping |
| Thread session explicitly through call chains | Same opt-in polarity with more plumbing; `safe_dump` lambdas and model-layer guards have no session parameter to receive |

**Deletions.** With the chokepoint in place, the per-consumer wiring is removed: `entitlements_for_request`, `limit_for_request`, the org serializer carve-out (entitlements/limits return to the bootstrap payload), `organizationStore.fetchEntitlements` merge-and-clobber, and `PlanPreviewModal.syncPreviewState()` shrinks to a bootstrap refresh plus `fetchOrganizations()`. Net-negative LOC.

## Trade-offs

- **We lose**: explicit data flow — the override is ambient request state rather than a passed parameter, invisible in method signatures.
- **We gain**: a single application point to implement, test, and audit; preview correctness for every current and future consumer; deletion of three special-cased sync paths that kept breaking.
- **Risk**: a leaked Fiber-local would bleed preview state across requests. Mitigated by middleware `ensure`-clearing plus defensive clear-on-set, the same discipline `connection_pinning.rb` already exercises.

## Implementation Notes

### Ordering constraint (2026-07-07)

The context-setting middleware must run after session middleware and before any controller that serializes organizations. Concrete placement: the universal stack (`lib/onetime/application/middleware_stack.rb`) mounts `Onetime::Session` for all three apps (web, api, internal); insert the preview-context middleware immediately after `Onetime::Middleware::IdentityResolution` (middleware_stack.rb:332). One mount point covers `/api/organizations`, `/api/colonel/*`, domain config endpoints, and the bootstrap serializer path — no per-app wiring.

### MRO placement (2026-07-07)

`Organization#entitlements` resolves to `WithPlanEntitlements#entitlements` (with_plan_entitlements.rb:177), which reaches the base via `super` only on the materialized branch — the standalone fail-open and Plan.load fallback branches return without it. A consult placed only in the base would therefore be skipped for non-materialized orgs. Implement the consult as one private helper in the base (`preview_entitlements` → reconciled array or nil) and guard the **top** of both `WithPlanEntitlements#entitlements` and `WithEntitlements#entitlements` with it. Preview state can only exist when a colonel set it via the billing-mode endpoint, so the guard is a no-op in standalone.

### Body-laziness constraint (2026-07-07)

`ensure`-clearing in the middleware is correct because all response bodies are serialized eagerly (JSON strings built in-handler). If a streaming/lazy body ever consumes entitlements during server-side body iteration, the clear must move to `Rack::BodyProxy#on_close`. Noted so the leak isn't introduced silently.

### Membership preview gate (2026-07-07)

The preview branch in `OrganizationMembership#entitlements` keys off the Fiber-local's presence, not off `entitlements_materialized?` — the whole point is that materialized state is *ignored* during preview. The colonel-only write path needs no membership-side counterpart: the Fiber-local is populated from the same session keys `SetEntitlementPreview` already writes.

### Same-request visibility (2026-07-07)

The middleware stashes the context before the handler runs, so a request that *changes* preview state would otherwise serialize its own response from the stale pre-flip context. `SetEntitlementPreview` must mirror its session writes into the Fiber-local (set → populate, clear → clear) so the flipping request's own response reflects the new state (`set_entitlement_preview.rb:194`).

### Reconciler DB client (2026-07-07)

The historical root cause of "preview keeps not working," and the biggest single insight of the design session. `reconcile_with_session_overrides` originally called `Familia.redis`, which does not exist in Familia 2.x — the reconciler raised `NoMethodError` the instant it was reached, so session-override reconciliation *never executed at runtime*, regardless of which consumers were wired. This is why per-consumer patches never held: even the one opted-in consumer's reconciliation path was dead code. Fixed to `Familia.dbclient` (`with_materialized_entitlements.rb:209`). It validates the ADR's premise from the other direction — the opt-in polarity hid a hard runtime failure, and correcting polarity without correcting the client would still have produced nothing. Called out here (not only in commit `6bbb7fe15`) because it is a live upgrade-hazard pattern worth a team heads-up: any `Familia.redis` callsite is a latent `NoMethodError`.

### Clear-before-baseline-read (2026-07-07)

`set_test_mode` builds the session revokes set from the org's *actual* entitlements — the baseline the preview "resets" from. But `organization.entitlements` is now preview-aware through the first chokepoint. If an in-flight preview context is present — switching preview from plan A to plan B within one session — reading the baseline would return A's *reconciled* view, baking A's grants into B's revokes and leaking actual entitlements through the new preview. `set_test_mode` therefore calls `Onetime::EntitlementPreview.clear` before reading `organization.entitlements` (`set_entitlement_preview.rb:163`). This is the mirror image of the Same-request visibility note: that one *sets* the Fiber-local after the write so the flip is visible; this one *clears* it before the baseline read so the flip is clean. A maintainer "simplifying" either away reintroduces a leak.

## Other notes

1. Smaller items documented only in agent output: the process_without_reconciler fallback yields a planid-only context (limits preview works, entitlement reconciliation inactive — legacy-mirroring, not a gap); the bootstrap serializer now shares safe_dump's PlanCacheMissError fail-closed exposure; the frontend currentOrganization ref staleness trap for future consumers; and GET /billing/api/entitlements/:extid now has zero frontend callers (delete-or-keep is an open decision).
