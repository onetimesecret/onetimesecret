// src/apps/admin/composables/useAdminDestructiveMutation.ts

import { useAdminMutation, type UseAdminMutation } from './useAdminMutation';
import { useColonelElevation } from './useColonelElevation';

/**
 * A TIER 1 (destructive) admin mutation — the same surface as
 * {@link useAdminMutation}, plus the #4327 step-up loop.
 *
 * Drop-in: `useAdminMutation(fn)` becomes `useAdminDestructiveMutation(fn)` and
 * the view keeps binding `loading` / `error` / `run` / `reset` exactly as before.
 * The sudo prompt is mounted ONCE in AdminLayout and driven through the shared
 * elevation state, so no view has to render or own it.
 *
 * ## The loop
 *
 *   attempt → 403 elevation_required → prompt → operator acts → retry ONCE
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

export type AdminGuardCode = (typeof BACKEND_CODE_MAP)[keyof typeof BACKEND_CODE_MAP] | null;

/**
 * @param error the raw thrown value from a failed mutation
 * @returns the typed guard failure, or null when the error is something else
 */
export function resolveGuardCode(error: unknown): AdminGuardCode {
  const response = (error as { response?: ErrorResponseLike } | null)?.response;
  const code = response?.data?.error_code;
  if (typeof code === 'string' && code in BACKEND_CODE_MAP) {
    return BACKEND_CODE_MAP[code as keyof typeof BACKEND_CODE_MAP];
  }
  return null;
}

export function useAdminDestructiveMutation<TArgs extends unknown[]>(
  perform: (...args: TArgs) => Promise<unknown>
): UseAdminMutation<TArgs> {
  const mutation = useAdminMutation(perform);
  const elevation = useColonelElevation();

  async function run(...args: TArgs): Promise<boolean> {
    if (await mutation.run(...args)) return true;
    if (resolveGuardCode(mutation.lastError.value) !== 'needs_elevation') return false;

    // The server refreshes what the console knows about this account's factors
    // on the same fetch that opens the prompt.
    if (!(await elevation.requestElevation())) return false;

    // Exactly one retry, after the operator's gesture.
    return mutation.run(...args);
  }

  return { ...mutation, run };
}
