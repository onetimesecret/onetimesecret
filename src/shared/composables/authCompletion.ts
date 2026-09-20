// src/shared/composables/authCompletion.ts

import type { RefreshOutcome, RefreshRequest } from '@/shared/stores/authStore';
import type { ClientAuthStatus } from '@/schemas/contracts/bootstrap';

/**
 * Structural subset of `useAuthStore()` this module needs. Declared locally
 * so callers can pass the store directly without a cast: the returned Pinia
 * store type unwraps computed refs to booleans that don't line up nominally
 * with `AuthStore`.
 */
interface AuthCompletionStore {
  readonly authStatus: ClientAuthStatus;
  setAuthenticated: (value: boolean) => Promise<RefreshOutcome | 'noop'>;
  refresh: (request: RefreshRequest) => Promise<RefreshOutcome>;
}

/**
 * ═══════════════════════════════════════════════════════════════════════════════
 * AUTH-COMPLETION CALLER CONTRACT (#4497 Arc A)
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * A caller finishing a first-factor auth POST and needing to navigate to an
 * authority-derived destination (/mfa-verify, Dashboard) MUST check three
 * independent conditions before navigating:
 *
 *   1. outcome !== 'superseded' — no-op if a newer coordinator run owns this.
 *   2. outcome === 'applied'   — else retry VERIFICATION (never the auth POST).
 *   3. authStatus matches the intended destination — else keep retrying.
 *
 * Rationale (ADR-046, .plans/4497-transition-contracts.md §1):
 *
 * A first-factor auth POST may be single-use (nonce, rate-limit, lockout
 * counter). On refresh failure retry the CHEAP idempotent step (`refresh`),
 * not the EXPENSIVE consumable step (the POST).
 *
 * `'superseded'` is not a failure: it is the correct answer when a newer
 * coordinator run has already reconciled. Treat it as success-by-delegation
 * and do not navigate — the newer run owns the destination.
 */

/** Additional outcome the caller sees when the local status is stably wrong. */
export type CompletionOutcome = RefreshOutcome | 'noop' | 'status-mismatch';

/**
 * Bounded retry schedule, in milliseconds. Two additional verification
 * attempts after the initial setAuthenticated call — small enough that a
 * transient blip is masked, short enough that the user is not left waiting
 * for a long time before we surface the error.
 */
const RECOVERY_DELAYS_MS = [300, 900] as const;

/**
 * Delay helper. Extracted so tests can substitute a synchronous scheduler.
 */
async function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Retries `refresh({ kind: 'ordinary', reason: '<caller>-recovery' })` up to
 * two times, waiting 300ms then 900ms between attempts. Returns the outcome
 * of the last attempt.
 *
 * The recovery kind is deliberately `ordinary`, NOT `auth-mutation`: we are
 * NOT repeating the login/MFA/link POST (that is single-use). We are
 * repeating verification of the state the server already recorded.
 */
async function retryVerification(
  authStore: AuthCompletionStore,
  _callerReason: string
): Promise<RefreshOutcome> {
  let outcome: RefreshOutcome = 'failed';
  for (const delay of RECOVERY_DELAYS_MS) {
    await sleep(delay);
    outcome = await authStore.refresh({
      kind: 'ordinary',
      reason: 'retry',
    });
    // A superseded reply means a newer op reconciled; hand it back so the
    // caller can no-op. An applied reply is our success signal.
    if (outcome === 'applied' || outcome === 'superseded') return outcome;
  }
  return outcome;
}

/**
 * Wait for the coordinator to land the tab in `authenticated` after a
 * primary-factor auth POST. Callers navigating to Dashboard should call
 * this and only route on the `'applied'` return.
 *
 * The initial `setAuthenticated(true)` outcome is checked first; on any
 * non-`applied`, non-`superseded` outcome, verification is retried. If the
 * final outcome IS `applied` but the store's status is not `authenticated`
 * (server reported anonymous, mfa_pending etc.), the return is
 * `'status-mismatch'` — the caller should NOT navigate to the protected
 * destination.
 *
 * @param authStore  The pinia auth store.
 * @param caller     Diagnostic tag included in the recovery reason.
 * @returns The refined completion outcome (see CompletionOutcome).
 */
export async function ensureAuthenticated(
  authStore: AuthCompletionStore,
  caller: string
): Promise<CompletionOutcome> {
  const initial = await authStore.setAuthenticated(true);
  // Local sign-out path returned 'noop' — callers never invoke this after
  // setAuthenticated(false), but keep it explicit.
  if (initial === 'noop') return 'noop';
  if (initial === 'superseded') return 'superseded';

  const outcome = initial === 'applied' ? initial : await retryVerification(authStore, caller);
  if (outcome === 'superseded') return 'superseded';
  if (outcome !== 'applied') return outcome;

  return authStore.authStatus === 'authenticated' ? 'applied' : 'status-mismatch';
}

/**
 * Wait for the coordinator to land the tab in `mfa_pending` after a
 * primary-factor auth POST that returned `mfa_required`. Callers routing to
 * /mfa-verify should call this and only push on the `'applied'` return.
 *
 * Unlike `ensureAuthenticated`, this uses a plain `refresh` (not
 * `setAuthenticated`) because the caller is not completing sign-in; it is
 * establishing the mfa_pending state so the /mfa-verify guard admits the
 * next hop.
 */
export async function ensureMfaPending(
  authStore: AuthCompletionStore,
  caller: string
): Promise<CompletionOutcome> {
  const initial = await authStore.refresh({
    kind: 'auth-mutation',
    reason: 'login',
  });
  if (initial === 'superseded') return 'superseded';

  const outcome = initial === 'applied' ? initial : await retryVerification(authStore, caller);
  if (outcome === 'superseded') return 'superseded';
  if (outcome !== 'applied') return outcome;

  return authStore.authStatus === 'mfa_pending' ? 'applied' : 'status-mismatch';
}
