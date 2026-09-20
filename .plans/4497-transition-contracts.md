# PR #4497 caller contracts (working note)

Reference for the review-feedback correction pass. Not an ADR — a short
transition table that all arcs implement against. Delete or fold into ADR-046
before merge.

## 1. Auth-completion contract (Arc A)

`refresh()` returns `RefreshOutcome ∈ {applied, superseded, refused, failed}`.
`setAuthenticated(value)` must propagate that outcome, not swallow it.

A caller finishing a first-factor auth POST and needing to navigate to an
authority-derived destination (`/mfa-verify`, Dashboard) MUST check three
independent conditions before navigating:

| # | Question                                          | Failure action              |
|---|---------------------------------------------------|-----------------------------|
| 1 | Do I still own this operation? (outcome ≠ `superseded`) | No-op; a newer op owns it. |
| 2 | Was a snapshot applied? (outcome === `applied`)   | Retry **verification** (a fresh `refresh({ kind: 'ordinary' })`), do NOT re-POST the auth mutation, do NOT navigate. Surface a retryable local error after N attempts. |
| 3 | Does the resulting status match the destination?  | Do NOT navigate to the wrong destination. Fall through to (2)'s retry, or surface an error if the mismatch is stable. |

Rationale: a first-factor auth POST may be single-use (nonce, rate-limit,
lockout counter). On refresh failure, retry the CHEAP idempotent step
(`refresh`), not the EXPENSIVE consumable step (POST).

`'superseded'` is not a failure: it is the correct answer when a newer
coordinator run has already reconciled. Treat it as success-by-delegation.

## 2. Recovery scheduling vs. withholding vs. action gating (Arcs B, C, D)

Three orthogonal axes. Each state decides each axis independently.

| State           | Recovery scheduled? | Route body withheld? | Identity visible? | Mutation actions? | Escape actions? |
|-----------------|---------------------|----------------------|-------------------|-------------------|-----------------|
| `authenticated` | interval + visibility | no                 | yes               | yes               | yes             |
| `mfa_pending`   | interval            | **yes**              | yes               | no (route body swap sends to `/mfa-verify`) | yes |
| `checking`      | already running     | yes                  | yes (last known)  | **no**            | yes             |
| `unavailable` (hydration) | **NEW: bounded retry from `init()`** | yes | yes (last known) | **no** | yes |
| `unavailable` (post-init) | continues from `noteFailure` | yes | yes | **no** | yes |
| `anonymous`     | none                | yes                  | no                | no                | n/a             |

**Escape actions** = sign-out, stop-impersonation. Always available when the
tab shows a retained identity, regardless of `authStatus`. A user who cannot
complete verification must still be able to leave.

**Retained identity is deliberate** (`isUserPresent` is correct). The bug is
that mutation controls were not gated separately.

**#11 (allocation-503) is a policy question, not part of this axis matrix.**
ADR-046 explicitly counts allocation failures toward `MAX_FAILURES`. Do not
change that threshold in this PR; call it out in the PR body as a follow-up.

## 3. Rejection disposition (Arc E)

The 401 interceptor and `useAsyncHandler` must not each maintain a copy of
"which scopes are coordinator-owned." That is the current bug.

Instead: the interceptor (or `noteApiRejection`) attaches an explicit
disposition to the failure:

```ts
type RejectionDisposition =
  | { ownedByCoordinator: true;  reason: 'reconciling' | 'will-reload' }
  | { ownedByCoordinator: false; reason: 'skipped-carve-out' | 'throttled' | 'nonauth' };
```

`useAsyncHandler` reads that field and suppresses the toast iff
`ownedByCoordinator === true`. The list of carve-outs and the throttle
decision live in **one** place (the coordinator). `useAsyncHandler` has no
list to keep in sync.

## 4. Generation ownership across async cleanup (Arc F)

`commit()` currently captures no generation snapshot before its awaits. Every
post-`await` step must be gated on `mine === generation`:

- Post-`await clearAccountScopedState()`: skip the whole tail (counter reset,
  timer schedule, `lastCheckTime` bump) if superseded.
- `clearAccountScopedState` itself should either be sequenced BEFORE
  `applySnapshot` (so the dynamic-import await happens while no snapshot has
  been visibly applied yet) OR each imported store's `reset` should short-
  circuit if `mine !== generation`. Prefer the first: it makes commit()
  atomic-looking from the caller's view.

Regression test target: two `refresh()` calls with overlapping in-flight
windows; assert the older one's post-await steps become no-ops.

## 5. Session-transition message hygiene (Arc G item 16)

Original suggestion "park only on `'reloading'`" is fragile: `reloading` means
`reload()` was called, not that the navigation actually succeeded. A user
cancelling a `beforeunload` prompt is not directly reported.

Corrected fix:

1. Stamp the parked message with `parkedAt` (Date.now()).
2. On read (`consumeSessionTransition`), discard if `now - parkedAt > TTL`
   (60s is plenty — a real reload consumes it within milliseconds).
3. Also clear the parked message in `commit()` on any successful
   reconciliation to the same or a newer generation, since a successful commit
   means the reload path is no longer the resolution.

TTL is the durable fix; commit-clear is the fast-path optimization.

## 6. Cross-boundary regression tests (add per arc)

Failing tests first, then fix. Priority ordering:

1. **Arc A**: successful auth POST + failed/`superseded` bootstrap refresh →
   assert no navigation and a local retryable error surfaces.
2. **Arc B**: `unavailable` hydration → assert bounded retry scheduled within
   one tick.
3. **Arc F**: older `commit()` completing after newer `refresh()` runs →
   assert older's post-await no-ops.
4. **Arc E**: 401 with `code_scope: 'customer_session'` but reconciliation
   throttled → assert user-visible feedback still surfaces.
5. **Arc C**: mounted protected page transitions in-place to `mfa_pending` →
   assert route body swaps.
