// src/apps/admin/utils/adminSessionExpiry.ts

import { ref, type Ref } from 'vue';

/**
 * The console's one view of "this admin session is over" (#4331).
 *
 * The server bounds the ADMIN API SURFACE (/api/colonel) with an idle and an
 * absolute timeout while leaving the shared onetime.session cookie alone. So the
 * /colonel shell keeps loading, the tenant app keeps working, and the only
 * signal the console gets is a 401 on its own API calls carrying the
 * {@link ADMIN_SESSION_EXPIRED_PREFIX} marker.
 *
 * ## Why a module-level ref and not a store
 *
 * Every admin request path — the paginated list fetch, the detail loader, every
 * mutation, and the elevation status read the console makes on entry — funnels
 * its catch through {@link noteAdminSessionExpiry}, and ONE banner in
 * AdminLayout renders the result. A per-component flag would let a list view
 * know the session is gone while a detail view beside it kept retrying.
 *
 * ## Why not a global Axios interceptor
 *
 * `errorInterceptor` is shared by every app and deliberately does no
 * gate-keeping; teaching it about an admin-only header would put admin policy in
 * everyone's request path. The four admin call sites are the whole surface.
 *
 * Nothing here polls. The flag is set by traffic the operator already caused,
 * which is the same reason the elevation composable has no timer: any periodic
 * request would refresh the server-side activity clock the idle bound reads and
 * silently disable it.
 */

/**
 * The server-side marker, from
 * `lib/onetime/application/auth_strategies/base_session_auth_strategy.rb`. Keep
 * the two in sync — this string IS the contract.
 */
export const ADMIN_SESSION_EXPIRED_PREFIX = '[ADMIN_SESSION_EXPIRED]';

/** True once any admin request has been refused for an expired admin window. */
export const adminSessionExpired: Ref<boolean> = ref(false);

/** Where to send the operator to replace the session, after it is cleared. */
export const ADMIN_SIGN_IN_PATH = '/signin?redirect=/colonel';

/**
 * Recover from an expired admin window (#4331).
 *
 * A bare link to {@link ADMIN_SIGN_IN_PATH} does NOT clear the window in simple
 * mode: while the shared `onetime.session` cookie still reads `authenticated`,
 * `GET /signin` short-circuits to "already logged in" WITHOUT re-stamping
 * `authenticated_at`
 * (`apps/web/core/controllers/authentication.rb#handle_already_authenticated`),
 * so the admin idle/absolute bound stays tripped and every `/api/colonel` call
 * keeps 401ing. The session must be CLEARED first; only then does the sign-in
 * actually re-authenticate and re-stamp. Full mode re-runs login regardless, but
 * routing both modes through logout is correct and keeps ONE recovery path.
 *
 * Best-effort logout (`GET /auth/logout` clears the session and renews the sid
 * server-side), then a HARD navigation to sign-in — deliberately not the SPA
 * router — so the sign-in page loads under the freshly cleared cookie.
 */
export async function recoverAdminSession(): Promise<void> {
  try {
    await fetch('/auth/logout', {
      method: 'GET',
      credentials: 'same-origin',
      headers: { Accept: 'application/json' },
    });
  } catch {
    // Even if logout fails (offline, blocked), still send them onward: the worst
    // case is the same dead-end they are already in, never worse.
  }
  window.location.assign(ADMIN_SIGN_IN_PATH);
}

interface ErrorBodyLike {
  status?: number;
  data?: { error?: unknown; message?: unknown };
}

function responseOf(error: unknown): ErrorBodyLike | undefined {
  return (error as { response?: ErrorBodyLike } | null)?.response;
}

/**
 * Flip the shared flag when `error` is the admin-session-expired 401.
 *
 * Otto renders an auth failure as `{error: 'Authentication Required', message:
 * '<reason>'}`, so the marker arrives in `message`; `error` is checked too so a
 * future handler that promotes the reason to the top-level field still matches.
 *
 * @returns true when this error was the expired-admin-session 401
 */
export function noteAdminSessionExpiry(error: unknown): boolean {
  const response = responseOf(error);
  if (response?.status !== 401) return false;

  const carriesMarker = [response.data?.message, response.data?.error].some(
    (value) => typeof value === 'string' && value.startsWith(ADMIN_SESSION_EXPIRED_PREFIX)
  );
  if (!carriesMarker) return false;

  adminSessionExpired.value = true;
  return true;
}

/** Test seam, and the reset a future re-authentication flow would call. */
export function clearAdminSessionExpired(): void {
  adminSessionExpired.value = false;
}
