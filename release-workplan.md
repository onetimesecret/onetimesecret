# Release Workplan - Authentication consistency: v0.26.13, v0.27.0, and backlog

Decision model: based on ADR-045. Snapshot ordering: ADR-046.

Tracking: epic #4451. Issue numbers below are its sub-issues.

## v0.26.13 — Resolve the shared authentication design

The release outcome is consistent authentication across server routing, bootstrap, Vue navigation, and protected APIs, with explicit recovery from unavailable verification and deterministic client-side snapshot ingestion.

| Work package                                         | Expected impact                       | Initial tension → target | Earlier items |
| ---------------------------------------------------- | ------------------------------------- | ------------------------ | ------------- |
| Shared server session evaluation                     | High: security, privacy, clarity      | High → low               | 1–7           |
| Unified client state, ordering, and navigation       | High: UX, security, functionality     | High → low               | 8–10          |
| Passive checks and failure recovery                  | High: security, UX                    | High → low               | 11–13         |
| Scoped caching, diagnostics, and regression coverage | Medium: privacy, clarity, reliability | Low–medium → low         | 15–17         |

Implement in this order:

1. **Establish the failure matrix.** (#4452) Exercise protected HTML, hydrated HTML, `GET /bootstrap/me`, and protected APIs with revoked, inactive, absolutely expired, MFA-pending, suspended, credential-stale, and tenant-surface-mismatched sessions, plus authentication-database failure. Identify where verdicts diverge and confirm the precise rejection behind the reported incident. Capture refusal codes and request IDs without recording credentials.

2. **Extract the common session evaluator.** (#4453) Reuse the existing checks and their ordering. Return a typed verdict with the verified principal/effective identity only on success. Protected HTML and APIs enforce that verdict; public routes remain reachable but hydrated and fetched bootstrap payloads serialize authenticated identity only after success. Keep route-specific authorization and admin API expiry outside the shared customer-authentication predicate.

3. **Preserve existing policy boundaries explicitly.** (#4454) Keep configured deadlines, authentication-mode behavior, and the current legacy unstamped-session exemption unchanged in this release. Test and document the exemption rather than accidentally treating it as verified active-session membership. Preserve MFA-pending as a limited state, with no customer object or protected account data.

4. **Separate verification from activity.** (#4455) Bootstrap and timer-driven checks verify revocation and deadlines without refreshing active-session `last_use` or admin activity metadata. Eligible authenticated requests retain current activity behavior. An expired or refused request never advances its activity deadline. Request-level memoization must not allow a passive check to suppress a later legitimate activity update.

5. **Make hydration the initial canonical snapshot.** (#4456) Continue injecting complete bootstrap data before Vue mounts. Route guards and initial components consume the hydrated snapshot synchronously; remove the unconditional startup refresh from `src/shared/components/layout/MastHead.vue`. A valid hydrated page makes zero startup requests to `GET /bootstrap/me`. Missing or invalid hydration enters an explicit checking or unavailable state instead of silently becoming anonymous.

6. **Add ordered snapshot ingestion per ADR-046.** (#4457 server allocation, #4464 client acceptance, #4465 forced page load and `beforeunload` guard) ADR-046 (Bootstrap State Ordering Contract) is normative for field definitions, server allocation, client acceptance rules, failure behavior, and the test list. This plan does not restate them; where this plan or a sub-issue differs from the ADR, the ADR wins. The outcomes this release depends on:
   - Complete snapshots carry `snapshot_epoch` and `snapshot_version` through both HTML hydration and `GET /bootstrap/me`. Those two fields and the client request generation decide order. `snapshot_generated_at` is diagnostic-only and never decides whether a snapshot is applied.
   - The fields pass through `apps/web/core/views/serializers/system_serializer.rb`, `src/schemas/contracts/bootstrap.ts`, `src/shared/stores/bootstrapStore.ts`, and `src/services/bootstrap.service.ts`.
   - The hydrated snapshot establishes the initial watermark. Stale state never replaces newer state, and the end of a session always reaches the tab.
   - Acceptance and the commit of all snapshot-derived state are one transaction. A refused snapshot mutates nothing, and the client never stays indefinitely on state it has refused to replace. Local state patches never advance the watermark.
   - Where the ADR ends in a page load, views holding unsubmitted input are protected by one shared `beforeunload` guard, starting with the secret creation form. Secret drafts are never persisted to browser storage.

7. **Make frontend authentication a single state transition.** (#4458) Use the bootstrap store as the canonical client state; route and component accessors derive from it. Model `checking`, `authenticated`, `anonymous`, `mfa_pending`, and `unavailable`. Remove the independent mutable authentication authority and the `sessionStorage.ots_auth_state` resurrection path. Retain `had_valid_session` temporarily for compatibility, but remove every authentication decision based on it and mark it deprecated. Replace authenticated fields atomically and clear customer, organization, receipts, diagnostics identity, impersonation, and other account-scoped context when authority is lost or the account changes.

8. **Unify refresh and navigation.** (#4459) Route guards, masthead actions, scheduled checks, and protected-API reconciliation use one refresh coordinator. Refresh only after authentication mutations such as login, logout, MFA completion, impersonation, or account switching; when returning to a stale visible tab; at the passive verification interval; after a rejection requiring reconciliation; or on explicit retry.

   The coordinator must deduplicate equivalent requests, allow at most one ordinary refresh in flight, give every request for a complete snapshot the next request generation, and cancel or invalidate obsolete generations. Authentication mutations invalidate older refresh generations. A response may be ingested only when its generation is still current and it passes the ADR-046 epoch and version acceptance rules. An older response must never restore identity after a later rejection, logout, or account change. A server-verified hydrated snapshot can satisfy initial navigation; rejected, checking, or unavailable state cannot redirect `/signin` to Dashboard using cached authentication.

9. **Handle rejection and unavailability distinctly.** (#4460) A definitive session rejection atomically clears protected client state and opens the appropriate sign-in or MFA flow. Network failure or unverifiable authority blocks protected content and actions, preserves the server session and last accepted snapshot internally, and shows a retryable verification-unavailable view without exposing protected UI from stale state. Remove automatic logout caused solely by repeated transport failures; a 503 from `GET /bootstrap/me` counts as a failed refresh, and repeated failures lead to the verification-unavailable view, not logout. Keep admin-expiry recovery scoped to the admin surface. Protected API rejection requests reconciliation through the coordinator rather than directly mutating authentication state.

10. **Include adjacent, low-tension protections.** (#4461) Apply `Cache-Control: private, no-store` to personalized HTML and bootstrap/authentication-state responses. Redact credentials at diagnostic sinks touched by this work. Add one user-facing session-transition message instead of repeated authentication toasts.

### Interfaces and compatibility

Tracked in #4462.

- Add `auth_status` to bootstrap: `authenticated`, `anonymous`, `mfa_pending`, or `unavailable`. Keep existing `authenticated` and `awaiting_mfa` fields as consistent compatibility projections.
- Use client-only `checking` during unresolved initial verification.
- Add `snapshot_epoch`, `snapshot_version`, and `snapshot_generated_at` to every complete hydrated or fetched server snapshot under ADR-046. Only a degraded hydration payload may omit them, and then all three together.
- Add a stable `code` to session-authentication failures while preserving existing HTTP behavior and response fields. Public bootstrap remains accessible; protected HTML redirects and API refusals retain their current contracts.
- Handle codes by failure scope. A login credential rejection or admin-only timeout must not trigger a blanket customer-session logout.
- Coordinate backend/frontend deployment. Legacy payloads with `authenticated: false` may only withhold access; no compatibility path may promote them to authenticated. Once an ordered snapshot has been accepted, an unversioned payload cannot mutate state.

## v0.27.0 — Complete lifecycle and contract consolidation

These items have meaningful impact but introduce separate lifecycle, compatibility, or application-wide concerns. Establish their failure scenarios during v0.26.13; implement them together in v0.27.0.

| Work                                                                                                              | Reason for placement                                                                                                   |
| ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| #4466 — Session rotation and cookie-tossing protection across login, account switching, and privilege transitions | High impact and high tension; requires end-to-end coverage of all session establishment paths. Earlier item 14.        |
| #4467 — Revocation cascade across remember-me and other supported continuation mechanisms | Requires inventory and coordinated invalidation beyond bootstrap and Vue state.                                        |
| #4468 — Remove deprecated `had_valid_session` and obsolete client-state compatibility paths | Completes the v0.26.13 contract after rollout evidence. Earlier items 8–9.                                             |
| #4469 — Extend structured authentication codes and explicit route coverage throughout remaining auth/account routes | Builds on the proven contract without expanding the patch into every authentication endpoint. Earlier items 12–13, 17. |
| #4470 — Complete credential/PII redaction and personalized-response cache coverage across remaining sinks and endpoints | Broader inventory and verification than the current authentication path. Earlier items 15–16.                          |

A reproducible session-fixation, authorization-bypass, or credential-disclosure issue discovered during v0.26.13 assessment is promoted into the current release. Version placement must change when the evidence changes.

## Backlog — Evidence-triggered work

No issues are filed for these until the evidence exists.

- Separate admin-session credentials and per-surface activity clocks; retain existing scoped enforcement until a dedicated design is justified.
- Redesign session storage, encryption, or cookie technology only if a concrete deficiency is established. Existing mechanisms are reused and verified.
- Change inactivity/lifetime values only through an explicit policy decision; this incident alone does not establish better values.
- Add richer cross-tab coordination, proactive expiry warnings, or expanded session-management UX after the canonical state transitions are stable.
- Build additional observability infrastructure only if existing structured transition metrics cannot answer rollout questions.

## Verification, release gates, and reassessment

The v0.26.13 release gate is tracked in #4463.

- Test the same session fixtures through protected HTML, hydrated HTML, `GET /bootstrap/me`, and protected APIs. Assert a shared schema and consistent identity verdicts while preserving deliberate differences in response format and admin scope.
- Cover ADR-046's test list in full (#4457, #4464, #4465). The ADR owns that list; it is not restated here.
- Browser tests cover hydrated startup with zero `/bootstrap/me` requests, exactly one request for explicit stale-state recovery, refresh after idle/revocation, `/dashboard → /signin` without a Vue bounce, MFA completion, account switching, and retry after verification failure.
- Ordering tests prove newer snapshots replace state; a refused snapshot mutates no store; reverse-resolution order retains the newest eligible snapshot; local partial patches do not advance the watermark; authentication mutations invalidate late requests; and logout in another tab, session expiry, and server-side revocation all reach the tab.
- Account-transition tests prove omitted account-scoped fields are cleared. Strict rejection cannot be reversed by hydration, session storage, or a late response.
- Controlled-clock tests prove passive polling cannot extend inactivity, valid activity still advances it, absolute expiry holds, rejected requests cannot revive a session, and clock rollback retains
  accepted state while producing diagnostics.
- Verify anonymous, MFA-pending, checking, and unavailable transitions remove or block protected customer data as required. Temporary verification failure must block protected UI without destroying the server session.
- Verify `Cache-Control: private, no-store`, scoped authentication codes, diagnostic redaction, and a single user-facing session-transition message.
- Run focused frontend checks through the existing pnpm/Vitest commands. Run Ruby coverage only through the prescribed lane runner and only in a checkout already containing `.test-mode`; otherwise prepare an isolated test checkout.
- Ship the complete v0.26.13 authentication-consistency package as one coordinated backend/frontend change. Do not deploy an intermediate state where HTML, `GET /bootstrap/me`, route guards, API rejection handlers, or snapshot-ordering logic use competing authorities.
- During staging and rollout, review refusal codes, redirect loops, verification-unavailable rates, the ordering diagnostics ADR-046 defines, and bootstrap query/write behavior. Unexpected revocations or increased activity writes reopen the relevant assumption before broader rollout.

Assumptions: this plan categorizes the authentication work discussed here, not the entire release backlog. v0.26.13 may contain the larger shared-design change, as selected. Retryable blocking is the chosen outage behavior because it preserves recovery while withholding protected access when verification is unavailable. Snapshot ordering follows ADR-046: a session-scoped epoch and version decide order in v0.26.13, and the generation timestamp is diagnostic-only.
