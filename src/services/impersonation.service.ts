// src/services/impersonation.service.ts

/**
 * Impersonation Service
 *
 * The customer-surface half of colonel impersonation: ending a support
 * session. Starting one is a colonel-API call and lives with the admin
 * console (AdminCustomerDetail.vue).
 *
 * While a marker is active the server answers every non-GET request with
 * 403 `{ error: 'impersonation_read_only' }` — EXCEPT this stop endpoint,
 * which is explicitly exempt. That exemption is why the path is a single
 * exported constant: it is a value the backend middleware and this module
 * must agree on exactly, and a rename on either side must be a one-line
 * change here.
 */

import { createApi } from '@/api';
import { createApiResponseSchema } from '@/schemas/api/base';
import type { AxiosInstance } from 'axios';
import { z } from 'zod';

/**
 * POST target that ends the active impersonation.
 *
 * Deliberately NOT under `/api/colonel/*`: that prefix is blocked outright
 * while impersonating (and is subject to admin network isolation), so a stop
 * button hosted there could never be pressed. It is a session-authenticated
 * customer-surface route; the server 404s it for sessions with no marker
 * rather than revealing that the endpoint exists.
 */
export const IMPERSONATION_STOP_PATH = '/api/account/impersonation/stop';

/** Where the operator lands if the server names no redirect target. */
export const IMPERSONATION_STOP_FALLBACK_PATH = '/colonel';

export const impersonationStopRecordSchema = z.object({
  stopped: z.boolean(),
  target_extid: z.string(),
  /** Console path to return to — normally the target's customer detail page. */
  redirect: z.string().nullish(),
});

export const impersonationStopResponseSchema = createApiResponseSchema(
  impersonationStopRecordSchema
);

export type ImpersonationStopRecord = z.infer<typeof impersonationStopRecordSchema>;
export type ImpersonationStopResponse = z.infer<typeof impersonationStopResponseSchema>;

/**
 * Lazily-initialized Axios instance. Mirrors billing.service.ts: this module is
 * plain (not a composable) and cannot inject(), and the banner it serves is
 * mounted in BOTH bundles, only one of which provides an instance.
 */
let _defaultApi: AxiosInstance | null = null;
function getDefaultApi(): AxiosInstance {
  if (!_defaultApi) _defaultApi = createApi();
  return _defaultApi;
}

/**
 * HTTP status from a rejected request, whatever shape the error arrives in.
 *
 * Read off `.response` rather than gated on `instanceof AxiosError`: errors
 * thrown by axios-mock-adapter in the test harness are NOT AxiosError
 * instances (the shared classifier's `isHttpError` misses them for that
 * reason), but they DO carry `.response`. Reading the field directly keeps
 * one code path working in both the harness and production.
 */
function statusOf(error: unknown): number | undefined {
  return (error as { response?: { status?: number } } | null)?.response?.status;
}

/**
 * Ends the active impersonation and returns the path to navigate to.
 *
 * Two DIFFERENT conditions both mean "you are no longer impersonating", and
 * both must land the operator back in the console:
 *
 *  - **2xx** — the stop succeeded. The body is parsed, not trusted: a
 *    malformed ack still means the server ended it, so we degrade to the
 *    console fallback instead of throwing and stranding the operator inside a
 *    session they asked to leave.
 *  - **404** — there was no marker to stop. The endpoint 404s for sessions
 *    with no active impersonation (it does not reveal itself to ordinary
 *    sessions), so this is the EXPIRED / already-cleared case, not a failure.
 *    Treating it as retryable would leave a banner on screen offering to end
 *    a session that is already over.
 *
 * Every other non-2xx (403, 5xx, network) DOES throw: the marker is presumed
 * still active and the caller must say so rather than navigate away.
 */
export async function stopImpersonation(api?: AxiosInstance): Promise<string> {
  const client = api ?? getDefaultApi();

  let response;
  try {
    response = await client.post(IMPERSONATION_STOP_PATH);
  } catch (error) {
    if (statusOf(error) === 404) return IMPERSONATION_STOP_FALLBACK_PATH;
    throw error;
  }

  const parsed = impersonationStopResponseSchema.safeParse(response.data);
  return parsed.success
    ? (parsed.data.record.redirect ?? IMPERSONATION_STOP_FALLBACK_PATH)
    : IMPERSONATION_STOP_FALLBACK_PATH;
}
