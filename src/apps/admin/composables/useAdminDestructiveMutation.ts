// src/apps/admin/composables/useAdminDestructiveMutation.ts

import { useI18n } from 'vue-i18n';

import { useAdminMutation, type UseAdminMutation } from './useAdminMutation';
import { useColonelElevation } from './useColonelElevation';

/**
 * A TIER 1 (destructive) admin mutation — the same surface as
 * {@link useAdminMutation}, plus the #4327 step-up loop and the #4329
 * rate-limit copy.
 *
 * Drop-in: `useAdminMutation(fn)` becomes `useAdminDestructiveMutation(fn)` and
 * the view keeps binding `loading` / `error` / `run` / `reset` exactly as before.
 * The sudo prompt is mounted ONCE in AdminLayout and driven through the shared
 * elevation state, so no view has to render or own it.
 *
 * ## Elevate first: `ensureElevated` in the opener
 *
 * The opener of every TIER 1 action (the backend's
 * `ColonelAPI::DestructiveActions::TIER1`) starts with
 *
 *   if (!(await ensureElevated())) return;
 *
 * and only then opens its own confirmation dialog. The dialog collects the
 * typed token and the operator's reason; it must collect them ONCE, after the
 * credential. Prompting only on the 403 meant the dialog closed under the
 * operator, the reason was lost, and they could not tell whether the action
 * had run. A cancelled prompt opens nothing and reports nothing.
 *
 * It is returned from here rather than imported per view so the guard sits
 * next to the mutation it protects. One mutation can serve several verbs of
 * different tiers (AdminCustomerDetail's role/verify/suspend/purge switch), so
 * the opener decides per verb; TIER 2 verbs (suspend, unverify, replay, run
 * chore, impersonate, ...) never call it.
 *
 * ## The fallback loop
 *
 *   attempt → 403 elevation_required → prompt → operator acts → retry ONCE
 *
 * The opener's guard leaves this for a window that lapses while the dialog is
 * open. The 403 overrules any countdown still showing locally (see
 * `noteElevationRequired`), so the prompt opens rather than a blind retry.
 *
 * The retry happens only AFTER the operator completes the prompt. It is never
 * silent: an automatic elevate-and-retry would put the whole flow back where the
 * security review found it, with a colonel session alone sufficient for a
 * destructive verb. If the operator cancels, the ORIGINAL error is surfaced
 * unchanged, and nothing is retried.
 *
 * Only ONE retry, and only when the retry itself is not another
 * elevation_required — otherwise a server that keeps refusing would loop the
 * operator through the prompt indefinitely.
 *
 * ## Rate limiting (#4329)
 *
 * A 429 already reaches the operator: the shared classifier renders any 4xx
 * carrying an `error` string verbatim, so the server's per-bucket message shows
 * up in the dialog with no frontend change. What this adds is the two things the
 * server message cannot say on its own — HOW LONG the wait is (from
 * `retry_after`) and HOW TO CLEAR IT. A colonel limiter is always keyed on the
 * ACTING colonel's extid, so an `error_type: 'LimitExceeded'` from this API is
 * always about the person reading the dialog; that is what makes the recovery
 * hint safe to append unconditionally.
 *
 * No global 429 interceptor: `errorInterceptor` deliberately does no
 * gate-keeping, and changing that would affect every app.
 */

/** Minimal shape of an Axios-like error's carried response body. */
interface ErrorResponseLike {
  status?: number;
  data?: Record<string, unknown>;
}

/**
 * The backend error codes this console branches on. Resolved from the BACKEND
 * CODE FIRST and the status family second (the useLinkSso idiom): 403 is shared
 * by "not a colonel", "no elevation", "wrong confirmation" and "elevation
 * attempt failed", so a status-first resolver would shadow every one of them.
 */
export const BACKEND_CODE_MAP = {
  elevation_required: 'needs_elevation',
  confirmation_required: 'needs_confirmation',
  elevation_failed: 'elevation_failed',
} as const;

/**
 * The status families that need a branch of their own. `Onetime::LimitExceeded`
 * carries no `error_code` — it predates the convention and is raised by a dozen
 * perimeter limiters — so 429 is recognised by status.
 */
export const STATUS_CODE_MAP = {
  429: 'rate_limited',
} as const;

export type AdminGuardCode =
  | (typeof BACKEND_CODE_MAP)[keyof typeof BACKEND_CODE_MAP]
  | (typeof STATUS_CODE_MAP)[keyof typeof STATUS_CODE_MAP]
  | null;

function responseOf(error: unknown): ErrorResponseLike | undefined {
  return (error as { response?: ErrorResponseLike } | null)?.response;
}

/**
 * @param error the raw thrown value from a failed mutation
 * @returns the typed guard failure, or null when the error is something else
 */
export function resolveGuardCode(error: unknown): AdminGuardCode {
  const response = responseOf(error);
  const code = response?.data?.error_code;
  if (typeof code === 'string' && code in BACKEND_CODE_MAP) {
    return BACKEND_CODE_MAP[code as keyof typeof BACKEND_CODE_MAP];
  }
  const status = response?.status;
  if (typeof status === 'number' && status in STATUS_CODE_MAP) {
    return STATUS_CODE_MAP[status as keyof typeof STATUS_CODE_MAP];
  }
  return null;
}

/**
 * Whole minutes the operator must wait, rounded UP so the console never tells
 * them to retry a second before the lockout expires. Null when the server sent
 * no usable `retry_after` — the server message then stands alone.
 */
export function retryAfterMinutes(error: unknown): number | null {
  const seconds = Number(responseOf(error)?.data?.retry_after);
  if (!Number.isFinite(seconds) || seconds <= 0) return null;
  return Math.max(1, Math.ceil(seconds / 60));
}

/** True for a 429 raised by an OTS limiter, as opposed to any upstream 429. */
function isOtsLimiterRejection(error: unknown): boolean {
  return responseOf(error)?.data?.error_type === 'LimitExceeded';
}

export interface UseAdminDestructiveMutation<
  TArgs extends unknown[],
> extends UseAdminMutation<TArgs> {
  /**
   * Resolve true once a step-up window is live (or step-up is disabled),
   * prompting first. Call it at the top of a TIER 1 opener — see the header.
   */
  ensureElevated: () => Promise<boolean>;
}

export function useAdminDestructiveMutation<TArgs extends unknown[]>(
  perform: (...args: TArgs) => Promise<unknown>
): UseAdminDestructiveMutation<TArgs> {
  const mutation = useAdminMutation(perform);
  const elevation = useColonelElevation();
  const { t } = useI18n();

  /** Append the wait and the recovery path to the server's own message. */
  function describeRateLimit(): void {
    const parts = [mutation.error.value];
    const minutes = retryAfterMinutes(mutation.lastError.value);
    if (minutes !== null) parts.push(t('web.admin.errors.rateLimited', { minutes }));
    if (isOtsLimiterRejection(mutation.lastError.value)) {
      parts.push(t('web.admin.errors.rateLimitedRecovery'));
    }
    mutation.error.value = parts.filter(Boolean).join(' ');
  }

  async function run(...args: TArgs): Promise<boolean> {
    if (await mutation.run(...args)) return true;

    const code = resolveGuardCode(mutation.lastError.value);
    if (code === 'rate_limited') {
      describeRateLimit();
      return false;
    }
    if (code !== 'needs_elevation') return false;

    // The server just said no window is live; a countdown still running here
    // must not short-circuit the prompt into a blind retry.
    elevation.noteElevationRequired();

    // The server refreshes what the console knows about this account's factors
    // on the same fetch that opens the prompt.
    if (!(await elevation.requestElevation())) return false;

    // Exactly one retry, after the operator's gesture.
    if (await mutation.run(...args)) return true;
    if (resolveGuardCode(mutation.lastError.value) === 'rate_limited') describeRateLimit();
    return false;
  }

  return { ...mutation, run, ensureElevated: elevation.ensureElevated };
}
