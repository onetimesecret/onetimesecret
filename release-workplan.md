release-workplan.md

# Release Workplan - Authentication consistency: v0.26.13, v0.27.0, and backlog

Decision model: based on ADR-045.

## v0.26.13 — Resolve the shared authentication design

The release outcome is consistent authentication across server routing, bootstrap, Vue navigation, and protected APIs, with explicit recovery from unavailable verification.

| Work package                                         | Expected impact                       | Initial tension → target | Earlier items |
| ---------------------------------------------------- | ------------------------------------- | ------------------------ | ------------- |
| Shared server session evaluation                     | High: security, privacy, clarity      | High → low               | 1–7           |
| Unified client state and navigation                  | High: UX, security, functionality     | High → low               | 8–10          |
| Passive checks and failure recovery                  | High: security, UX                    | High → low               | 11–13         |
| Scoped caching, diagnostics, and regression coverage | Medium: privacy, clarity, reliability | Low–medium → low         | 15–17         |

Implement in this order:

1. **Establish the failure matrix.** Exercise strict routes and public bootstrap with revoked, expired, MFA-pending, suspended, credential-stale, and surface-mismatched sessions, plus authentication-database failure. Identify where their verdicts diverge. Capture refusal codes and request IDs without recording credentials.

2. **Extract the common session evaluator.** Reuse the existing checks and their ordering. Return a structured verdict with the verified principal/effective identity only on success. Strict routes enforce that verdict; public routes remain reachable but serialize authenticated identity only after success. Keep route-specific authorization and admin API expiry outside the shared customer-authentication predicate.

3. **Preserve existing policy boundaries explicitly.** Keep configured deadlines, authentication-mode behavior, and the current legacy unstamped-session exemption unchanged in this release. Test and document the exemption rather than accidentally treating it as verified active-session membership. Preserve MFA-pending as a limited state, with no customer object or protected account data.

4. **Separate verification from activity.** Bootstrap and timer-driven checks verify revocation and deadlines without refreshing active-session `last_use` or admin activity metadata. Eligible authenticated requests retain current activity behavior. An expired or refused request never advances its activity deadline. Request-level memoization must not allow a passive check to suppress a later legitimate activity update.

5. **Make frontend authentication a single state transition.** Use the bootstrap store as the canonical client state; auth-store accessors derive from it. Remove the `sessionStorage` override. Retain `had_valid_session` temporarily for compatibility, but remove every authentication decision based on it and mark it deprecated. Replace authenticated fields atomically and clear customer, organization, receipt, and diagnostics context when authority is lost or the account changes.

6. **Unify refresh and navigation.** Route guards, masthead refreshes, and scheduled checks use one refresh operation with concurrent-request deduplication. Prevent an older response from restoring identity after a later rejection, logout, or account change. A server-verified initial bootstrap can satisfy initial navigation; a rejected or uncertain state cannot redirect `/signin` back to Dashboard using cached authentication.

7. **Handle rejection and unavailability distinctly.** A definitive session rejection clears protected client state and opens the appropriate sign-in/MFA flow. Network failure or unverifiable authority blocks protected content and actions, preserves the server session, and shows a retryable verification-unavailable view. Remove automatic logout caused solely by repeated transport failures. Keep admin-expiry recovery scoped to the admin surface.

8. **Include adjacent, low-tension protections.** Apply `private, no-store` response caching to personalized HTML and bootstrap/authentication-state responses. Redact credentials at diagnostic sinks touched by this work. Add one user-facing session transition message instead of repeated authentication toasts.

### Interfaces and compatibility

- Add an `auth_status` field to bootstrap: `authenticated`, `anonymous`, `mfa_pending`, or `unavailable`. Keep existing `authenticated` and `awaiting_mfa` fields as consistent compatibility projections.
- Use client-only `checking` state during unresolved initial verification.
- Add a stable `code` to session-authentication failures while preserving existing HTTP behavior and response fields. Public bootstrap remains accessible; protected HTML redirects and API refusals retain their current contracts.
- Handle codes by failure scope. A login credential rejection or admin-only timeout must not trigger a blanket customer-session logout.
- Coordinate backend/frontend deployment. During transition, legacy payloads with `authenticated: false` always remain unauthenticated; no compatibility path may promote them.

## v0.27.0 — Complete lifecycle and contract consolidation

These items have meaningful impact but introduce separate lifecycle, compatibility, or application-wide concerns. Establish their failure scenarios during v0.26.13; implement them together in v0.27.0.

| Work                                                                                                            | Reason for placement                                                                                                   |
| --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Session rotation and cookie-tossing protection across login, account switching, and privilege transitions       | High impact and high tension; requires end-to-end coverage of all session establishment paths. Earlier item 14.        |
| Revocation cascade across remember-me and other supported continuation mechanisms                               | Requires inventory and coordinated invalidation beyond bootstrap and Vue state.                                        |
| Remove deprecated `had_valid_session` and obsolete client-state compatibility paths                             | Completes the v0.26.13 contract after rollout evidence. Earlier items 8–9.                                             |
| Extend structured authentication codes and explicit route coverage throughout remaining auth/account routes     | Builds on the proven contract without expanding the patch into every authentication endpoint. Earlier items 12–13, 17. |
| Complete credential/PII redaction and personalized-response cache coverage across remaining sinks and endpoints | Broader inventory and verification than the current authentication path. Earlier items 15–16.                          |

A reproducible session-fixation, authorization bypass, or credential-disclosure issue discovered during v0.26.13 assessment is promoted into the current release. Version placement must change when the evidence changes.

## Backlog — Evidence-triggered work

- Separate admin-session credentials and per-surface activity clocks; retain existing scoped enforcement until a dedicated design is justified.
- Redesign session storage, encryption, or cookie technology only if a concrete deficiency is established. Existing mechanisms are reused and verified.
- Change inactivity/lifetime values only through an explicit policy decision; this incident alone does not establish better values.
- Add richer cross-tab coordination, proactive expiry warnings, or expanded session-management UX after the canonical state transitions are stable.
- Build additional observability infrastructure only if existing structured logs cannot answer rollout questions.

## Verification, release gates, and reassessment

- Test the same session fixtures through protected HTML, public-page serialization, bootstrap, and protected APIs. Assert consistent identity verdicts while preserving deliberate differences in response format and admin scope.
- Browser tests cover refresh after idle/revocation, `/dashboard → /signin` without a Vue bounce, MFA completion, account switching, concurrent/stale responses, and retry after verification failure.
- Controlled-clock tests prove passive polling cannot extend inactivity, valid activity still advances it, absolute expiry holds, and rejected requests cannot revive a session.
- Verify anonymous/MFA/unavailable payloads and client transitions remove protected customer data; verify response cache headers and diagnostic redaction.
- Run focused frontend checks and Ruby tests through the prescribed lane runner in a checkout with `.test-mode`. If the current checkout lacks it, prepare an isolated test checkout.
- Ship only when the complete authentication-consistency package passes. Do not release an intermediate state where server and client use competing verdicts.
- During staging and rollout, review refusal codes, redirect loops, verification-unavailable rates, and bootstrap query/write behavior. Unexpected revocations or increased activity writes reopen the relevant assumption before broader rollout.

Assumptions: this plan categorizes the authentication work discussed here, not the entire release backlog. v0.26.13 may contain the larger shared-design change, as selected. Retryable blocking is the chosen outage behavior because it preserves recovery while withholding protected access when verification is unavailable.

---

The following plan details are meant to dovetail with and where they overlap, supersede the Release Workplan.

<proposed_plan>

# Authentication consistency plan

## Ordering contract

Add `snapshot_generated_at` to every complete bootstrap payload:

- Format: fixed-width UTC RFC 3339 with exactly six fractional digits, for example `2026-09-17T17:28:59.123456Z`.
- Generate it once while building each server snapshot, after authentication resolution.
- Emit it through both the HTML hydration blob and `GET /bootstrap/me`.
- Validate the exact format in the shared Zod/Rhales schema.
- Compare the canonical strings directly. Do not convert through JavaScript `Date`, which discards microsecond precision.
- The hydrated HTML establishes the initial accepted watermark.
- Accept a complete snapshot only when its timestamp is strictly newer.
- Ignore equal or older snapshots atomically; they must not partially update any store.
- Local state patches never advance the watermark.
- Once a timestamped snapshot has been accepted, reject missing or malformed timestamps.

A datetime alone cannot mathematically guarantee total ordering across equal timestamps, clock rollback, or unsynchronized workers. Therefore deterministic correctness also requires:

- One shared refresh coordinator with at most one ordinary refresh in flight.
- A monotonically increasing client request generation for exceptional overlapping operations.
- Responses must satisfy both:
  - their server timestamp is newer than the accepted watermark; and
  - their request generation is still current.
- Authentication mutations cancel or invalidate older refresh generations.
- Record clock regressions as structured diagnostics and retain the last accepted state.
- If hard cross-worker total ordering is required independent of clock synchronization, add a server-authoritative monotonic `snapshot_version` alongside the datetime in v0.26.13. Do not claim the datetime alone provides that guarantee.

## v0.26.13

### 1. Establish the failure matrix

Test protected HTML, hydrated HTML, `/bootstrap/me`, and protected APIs for:

- Inactivity and absolute expiry
- Explicit revocation
- MFA pending
- Suspension
- Credential watermark failure
- Tenant-surface mismatch
- Authentication-database unavailability

Capture structured result codes and request IDs without credentials. Confirm the precise rejection behind the reported incident.

### 2. Use one server authentication evaluator

Extract one shared session evaluator producing a typed verdict and, only on success, an authenticated principal.

Reuse it for:

- Protected HTML routing
- Hydrated bootstrap authentication fields
- `GET /bootstrap/me`
- Protected APIs

Public routes remain accessible, but their bootstrap payload must not identify a user rejected by the shared evaluator. Route-specific authorization and admin lifetime policy remain separate layers.

### 3. Make hydration the initial snapshot

Continue injecting bootstrap data before Vue mounts and treat it as the complete initial server snapshot.

- Remove the unconditional `bootstrapStore.refresh()` from [MastHead.vue](/Users/d/Projects/dev/onetimesecret/onetimesecret/src/shared/components/layout/MastHead.vue:250).
- An ordinary hydrated page must make zero startup `/bootstrap/me` requests.
- Route guards and initial components consume the hydrated snapshot synchronously.
- Missing or invalid hydration enters an explicit checking/unavailable state instead of silently becoming anonymous.
- Personalized HTML and `/bootstrap/me` use `Cache-Control: private, no-store`.

### 4. Add snapshot time and ordered ingestion

Add `snapshot_generated_at` through:

- [system_serializer.rb](/Users/d/Projects/dev/onetimesecret/onetimesecret/apps/web/core/views/serializers/system_serializer.rb)
- [bootstrap.ts](/Users/d/Projects/dev/onetimesecret/onetimesecret/src/schemas/contracts/bootstrap.ts)
- [bootstrapStore.ts](/Users/d/Projects/dev/onetimesecret/onetimesecret/src/shared/stores/bootstrapStore.ts)
- [bootstrap.service.ts](/Users/d/Projects/dev/onetimesecret/onetimesecret/src/services/bootstrap.service.ts)

Create one ingestion operation for both hydrated and fetched payloads:

1. Validate the complete schema.
2. Check timestamp and request generation.
3. Reject stale payloads before mutation.
4. Replace all account-scoped state atomically.
5. Publish the new watermark only after the replacement succeeds.

Equal timestamps with different payloads are an invariant violation: retain the accepted snapshot, emit diagnostics, and schedule one coordinated retry.

### 5. Create one frontend authentication state machine

Make the bootstrap store the canonical state. Derive route and component authentication from it.

States:

- `checking`
- `authenticated`
- `anonymous`
- `mfa_pending`
- `unavailable`

Remove:

- The independent mutable `authStore.isAuthenticated` authority
- The `sessionStorage.ots_auth_state` resurrection path
- Decisions based on `had_valid_session`

Keep `had_valid_session` temporarily as a deprecated compatibility field, with no authorization or routing effect.

### 6. Coordinate refreshes

Replace the separate Fetch and Axios refresh paths with one coordinator.

Refresh only:

- After login, logout, MFA completion, impersonation, or account switching
- When returning to a stale visible tab
- At the passive verification interval
- Following an authentication rejection that requires reconciliation
- On explicit retry

The coordinator must:

- Deduplicate equivalent requests
- Assign request generations
- Cancel or invalidate obsolete requests
- Reject older timestamps
- Prevent an old response from restoring a previous identity
- Avoid modifying active-session `last_use` during passive verification

Protected API rejection should request reconciliation through this coordinator rather than directly mutating authentication state.

### 7. Separate rejection from unavailability

For definitive rejection:

- Atomically clear customer, organization, receipts, diagnostics identity, impersonation, and other account-scoped state.
- Route to sign-in or MFA as appropriate.
- Display one session-transition message, not repeated API toasts.

For verification unavailability:

- Block protected content and actions.
- Preserve the server session and last accepted snapshot internally, but do not expose protected UI from it.
- Show a retryable verification-unavailable screen.
- Do not automatically call logout because of transport failures.

Admin expiry remains scoped to the admin surface.

### 8. Verification

Add tests proving:

- HTML and `/bootstrap/me` share the schema, authentication verdict, and timestamp format.
- Hydrated startup performs zero `/bootstrap/me` requests.
- Explicit stale-state recovery performs exactly one request.
- Newer snapshots replace state.
- Equal, older, malformed, and unversioned responses cannot mutate state.
- Responses resolving in reverse order leave the newest snapshot installed.
- Differences below one millisecond remain correctly ordered.
- Local partial patches do not advance the server watermark.
- Account transitions clear omitted account-scoped fields.
- Passive polling does not extend inactivity.
- Strict rejection cannot be reversed by hydration, session storage, or a late request.
- Clock rollback retains the accepted state and produces diagnostics.
- Temporary verification failure blocks protected UI without destroying the session.

Run Ruby coverage only through the lane runner and only in a checkout already containing `.test-mode`. Run frontend tests through the existing pnpm/Vitest commands.

## v0.27.0

- Remove `had_valid_session` and remaining compatibility branches.
- Complete session rotation for login, account switching, and privilege changes.
- Complete revocation cascade, including remember-me and continuation credentials.
- Expand structured authentication codes across remaining routes.
- Finish credential/PII log redaction and personalized-response cache coverage.
- Add a centralized monotonic `snapshot_version` if v0.26.13 cannot establish a sufficiently strong server-clock invariant. Promote this into v0.26.13 if multiple unsynchronized workers are supported in the release configuration.

## Backlog

- Separate admin and customer cookies or activity clocks.
- Richer cross-tab session-transition coordination.
- Proactive expiry warnings.
- Session-storage/encryption redesign only in response to a demonstrated deficiency.
- Changes to inactivity or absolute deadlines only through an explicit policy decision.
- Additional observability only where the structured transition metrics prove insufficient.

## Release gate

Ship the v0.26.13 work as one coordinated backend/frontend change. Do not deploy an intermediate state where HTML, `/bootstrap/me`, route guards, or API rejection handlers use different authentication authorities or snapshot-ordering rules.
</proposed_plan>
