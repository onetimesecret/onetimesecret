# S3 — Revealed plaintext secret not cleared from SPA memory

- **Severity:** Medium
- **Status:** Proposed fix
- **Affects default config?** **No** (behavioral; independent of any config flag)
- **Related:** S1 (CSP is the control that gates the chained-XSS read this widens). Finding 05 #4.
- **Primary files:**
  - `src/shared/stores/secretStore.ts:203-218` (`clear()` / `$reset()` exist, never called from the reveal flow)
  - `src/shared/components/base/BaseShowSecret.vue:39,50-57` (central reveal container — owns the store via `useSecret`, has `onMounted`/`onBeforeRouteUpdate` but **no** `onBeforeUnmount` cleanup)
  - `src/apps/secret/composables/useSecretLifecycle.ts:62` (copies `secret_value` into a second `payload` ref — a separate residency point)
  - `src/apps/secret/components/canonical/SecretDisplayCase.vue:52-66` (copy-to-clipboard handler) and `branded/SecretDisplayCase.vue` (same pattern)

## Problem (recap)

After a recipient reveals a secret, the plaintext is written to the Pinia store
(`record.value.secret_value`, `secretStore.ts:189`) and stays on the JS heap, reachable through the
live store, until route teardown, tab close, or GC reclaims it — none of which is explicit or
prompt. `clear()` and `$reset()` exist (`secretStore.ts:203-218`) but **no component in the
reveal/display path calls them**: the only `onUnmounted` in the display components removes a resize
listener (`branded/BaseSecretDisplay.vue:84-86`), and the central container `BaseShowSecret.vue`
defines `onMounted`/`onBeforeRouteUpdate` (`:50-57`) with no unmount cleanup.

Severity is Medium, not High: reading the residual value still requires code execution in the page
(which the strict CSP — S1 — is designed to block) and the secret is one-time. The fix narrows the
window during which a chained XSS, heap dump, or memory-scrape could read an already-revealed value.

## Root cause

The store's lifetime is tied to the Pinia instance (app lifetime), not to the secret's display
lifetime. Nothing scopes the plaintext to "while the reveal view is mounted." The teardown hook that
*should* null the value was never wired up, and a second copy of the plaintext (`payload` ref in
`useSecretLifecycle.ts:62`) compounds the residency.

## Honest limitation (state up front)

JavaScript **cannot guarantee zeroization**. Strings are immutable; setting `record.value = null`
removes one *reference* but does not scrub the original bytes from the heap — the V8 GC reclaims them
on its own schedule, and intermediate copies (DOM `<textarea>.value` at
`canonical/SecretDisplayCase.vue:158`, clipboard, devtools retainers) may persist. The realistic,
defensible goal is **minimize lifetime and reference count**, not "secure erase." This should be
stated in the code comments and PR so reviewers don't over-claim. Anything stronger (e.g. holding the
ciphertext and decrypting into a transient buffer) is out of scope and only marginally better in a
managed runtime.

## Prescribed resolution

Scope the plaintext to the reveal view's lifetime and drop references as early as the UX allows.

### Implementation steps

1. **Clear the store when the reveal container unmounts.** In `BaseShowSecret.vue` add an
   `onBeforeUnmount` that calls the store's `clear()`. The container already pulls the store via
   `useSecret` (`BaseShowSecret.vue:39`); expose the store handle (or call `useSecretStore()`
   directly) and clear it:

   ```ts
   // BaseShowSecret.vue <script setup>
   import { onBeforeUnmount, onMounted } from 'vue';
   import { useSecretStore } from '@/shared/stores/secretStore';

   const secretStore = useSecretStore();
   // ...existing useSecret(props.secretIdentifier) wiring...

   onBeforeUnmount(() => {
     // Best-effort: drop the live reference to the revealed plaintext.
     // JS cannot guarantee zeroization; this minimizes residency, not eradicates it.
     secretStore.clear();
   });
   ```

   This is the single highest-value change: every reveal path (canonical and branded) renders through
   `BaseShowSecret`, so one hook covers all of them.

2. **Clear on navigation away within the SPA.** `onBeforeRouteUpdate` (`BaseShowSecret.vue:50-53`)
   reloads on identifier change but does not clear stale plaintext first. Call `secretStore.clear()`
   at the top of that handler (before `load()`), and add an `onBeforeRouteLeave` so leaving the
   reveal route also nulls the value:

   ```ts
   import { onBeforeRouteLeave, onBeforeRouteUpdate } from 'vue-router';

   onBeforeRouteUpdate((to, from, next) => {
     secretStore.clear();
     load();
     next();
   });
   onBeforeRouteLeave((to, from, next) => {
     secretStore.clear();
     next();
   });
   ```

3. **Eliminate the second copy in `useSecretLifecycle`.** `useSecretLifecycle.ts:62` assigns
   `payload.value = secretStore.record?.secret_value`, duplicating the plaintext into a ref the store
   can't clear. Prefer reading through the store/`details` on demand; if `payload` must stay for the
   state machine, null it in the same teardown path. Confirm current consumers of `useSecretLifecycle`
   first (`grep` shows it is referenced but verify no view relies on `payload` outliving the store).

4. **Drop the reference after the user is done (optional, UX-gated).** After a successful copy
   (`SecretDisplayCase.vue:52-66`, both canonical and branded) the value is in the clipboard and the
   user has what they need; you *may* clear the store then to shorten residency further. Do this only
   if product accepts that re-copy would require re-reveal (and a one-time secret usually can't be
   re-revealed anyway). Keep the on-screen `<textarea>` as the source of truth for that session if
   re-copy must work; otherwise clearing the store while the textarea still holds the value is
   honest but not a full scrub (see Limitation).

5. **Comment the intent** at `clear()` (`secretStore.ts:203`) and at each call site, stating this is
   best-effort lifetime minimization, not zeroization, so future maintainers preserve the behavior.

### Alternatives considered

- **Rely on GC / navigation only (status quo):** rejected — residency is unbounded and implicit;
  a single-page session that never navigates keeps the plaintext indefinitely.
- **`$reset()` instead of `clear()`:** `$reset()` also flips `apiMode` back to `authenticated` and
  `_initialized` to `false` (`secretStore.ts:212-218`), which would force a re-`init()` and could
  reset API mode mid-flow. Use the narrower `clear()` for teardown; reserve `$reset()` for
  logout/full-reset paths.
- **Attempt zeroization (overwrite buffers):** rejected — not achievable for JS strings; gives false
  assurance. Lifetime minimization is the correct, honest control.
- **Move plaintext out of Pinia into component-local state:** viable and arguably cleaner (ties
  lifetime to the component automatically), but a larger refactor than wiring teardown into the
  existing store. Note as a future option; the prescribed fix achieves the same residency window with
  far less churn.

## Test / verification

- **Unit (store):** extend `src/tests/stores/secretStore.spec.ts` — after `reveal()`, assert
  `store.record?.secret_value` is set; call `store.clear()`; assert `record`, `details`, `status`
  are all `null`. (Guards the contract the components depend on.)
- **Component (teardown):** with Vue Test Utils, mount `BaseShowSecret`, drive a reveal so
  `record.secret_value` is populated, then `wrapper.unmount()` and assert the store's `record` is
  `null`. Add a route-leave variant using a mocked router to assert `clear()` fires on
  `onBeforeRouteLeave`/`onBeforeRouteUpdate`.
- **Regression:** assert the on-screen reveal still renders the secret before unmount (the clear must
  not fire while the view is visible).
- **Manual:** reveal a secret, open devtools → Pinia/Vue panel, confirm `secrets.record` holds the
  value while displayed and becomes `null` immediately on navigating away or closing the view. Note in
  the PR that a heap snapshot may still show the bytes until GC — this is the documented JS limitation.

## Effort & risk

- **Effort:** Small. One `onBeforeUnmount` + two route guards in `BaseShowSecret.vue`, optional cleanup
  of the `useSecretLifecycle` duplicate, plus tests.
- **Risk:** Low. The main hazard is clearing too eagerly (blanking the display while the user is still
  reading) — avoided by clearing on **unmount/leave**, not on a timer, and gating the post-copy clear
  behind product sign-off. No config or server change; behavior is purely client-side.
