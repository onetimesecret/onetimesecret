// src/apps/admin/utils/operatorReason.ts

import type { AxiosRequestConfig } from 'axios';

/**
 * The OPTIONAL operator-supplied reason on a destructive colonel action (#4338).
 *
 * The admin audit trail records WHAT an operator did and to whom, but never
 * WHY. `AdminConfirmDialog` collects the why (see its `requestReason` prop) and
 * emits it with `confirm`; these helpers put it on the wire in the shape the
 * matching endpoint reads it from, so the choice is made once here instead of
 * at a dozen call sites.
 *
 * ## Body vs query, and why it is not a free choice
 *
 * DELETE request bodies are not reliably parsed across this stack — the colonel
 * DELETE endpoints already read `dry_run`, `force_default` and friends from the
 * QUERY STRING for exactly that reason. So:
 *
 *   - POST   -> {@link reasonBody} / {@link reasonBodyArgs}, in the JSON body
 *   - DELETE -> {@link reasonQueryArgs}, appended to the query string
 *
 * Server-side `params` merges both, so the Ruby adapters read `params['reason']`
 * identically either way (ColonelAPI::Logic::Base#operator_reason_param).
 *
 * ## Blank is ABSENT, and absent means BYTE-IDENTICAL
 *
 * With no reason these helpers add NOTHING to the request — not `reason=''`,
 * and not even an empty axios config object. That is why the `*Args` helpers
 * return a spreadable tuple rather than a value: `$api.delete(url,
 * ...reasonQueryArgs(undefined))` is exactly `$api.delete(url)`, so an action
 * taken without a reason is the same request it was before #4338, and its audit
 * `detail` keeps its pre-#4338 shape. An empty string in the trail would read
 * as "they gave a reason" when they did not.
 */

/** Longest reason the dialog accepts — mirrors Onetime::AuditReason::MAX_LENGTH. */
export const OPERATOR_REASON_MAX_LENGTH = 255;

/** Trimmed reason, or undefined when blank/absent. */
function normalize(reason?: string): string | undefined {
  const trimmed = reason?.trim();
  return trimmed ? trimmed.slice(0, OPERATOR_REASON_MAX_LENGTH) : undefined;
}

/**
 * Reason fragment to MERGE into a POST body that exists anyway:
 *
 *   $api.post(url, { role, ...reasonBody(reason) })
 */
export function reasonBody(reason?: string): { reason?: string } {
  const value = normalize(reason);
  return value ? { reason: value } : {};
}

/**
 * Spreadable body argument for a POST that otherwise sends none:
 *
 *   $api.post(url, ...reasonBodyArgs(reason))
 */
export function reasonBodyArgs(reason?: string): [] | [{ reason: string }] {
  const value = normalize(reason);
  return value ? [{ reason: value }] : [];
}

/**
 * Spreadable axios-config argument for a DELETE (or any call whose arguments
 * ride the query string):
 *
 *   $api.delete(url, ...reasonQueryArgs(reason))
 *
 * Axios appends `params` to a URL that already carries a query string, so this
 * composes with the `?dry_run=…` URLs the domain and organization deletes build.
 */
export function reasonQueryArgs(reason?: string): [] | [AxiosRequestConfig] {
  const value = normalize(reason);
  return value ? [{ params: { reason: value } }] : [];
}
