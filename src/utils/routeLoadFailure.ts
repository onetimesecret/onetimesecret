// src/utils/routeLoadFailure.ts
//
// A route whose chunk failed to load while the page declined to reload
// (src/utils/preloadError.ts: a one-time value on screen, a language switch
// in flight, or the ADR-046 bound spent). The navigation rejects and nothing
// renders: the URL stays, and the clicked link seems to do nothing. Vite's
// helper rethrows the error it attached to the event, the handler remembers
// it (wasLeftToFail), and the one router.onError below turns it into state
// for RouteLoadNotice, which names the problem and offers the manual reload
// that fixes a stale deployment. The record goes away with the next
// navigation that completes, or when the notice is dismissed.
//
// Shared by both bundles' routers (src/router/index.ts and
// src/apps/admin/router.ts), which is why it lives outside src/router: the
// admin bundle must not import the customer route graph.

import { loggingService } from '@/services/logging.service';
import { reloadPending, wasLeftToFail } from '@/utils/preloadError';
import { computed, shallowRef } from 'vue';
import type { Router } from 'vue-router';

export interface RouteLoadFailure {
  /** The location that could not open, as the router saw it. */
  path: string;
}

const failure = shallowRef<RouteLoadFailure | null>(null);

/** The failure on record, for RouteLoadNotice; null while there is none. */
export const routeLoadFailure = computed(() => failure.value);

/**
 * Registers the router hooks. A navigation that fails with an import the
 * preload handler left to fail is recorded. Any other navigation error is
 * logged, as vue-router prints it itself when no error handler is registered,
 * except while a reload of this page is pending: the import then resolved
 * with undefined and vue-router reports the missing component, which the
 * reload is about to replace. That reload normally replaces the page within
 * moments; a navigation that completes after it was requested means the page
 * stayed (the browser's beforeunload prompt was cancelled), and errors are
 * logged again from then on. A navigation that completes also clears the
 * record.
 */
export function watchRouteLoads(router: Router): void {
  let stayedAfterReload = false;
  router.onError((error, to) => {
    if (wasLeftToFail(error)) {
      recordRouteLoadFailure(to.fullPath);
      return;
    }
    if (reloadPending() && !stayedAfterReload) return;
    loggingService.error(error instanceof Error ? error : new Error(String(error)));
  });
  router.afterEach((_to, _from, navigationFailure) => {
    if (navigationFailure) return;
    failure.value = null;
    if (reloadPending()) stayedAfterReload = true;
  });
}

/** Records that `path` could not open; RouteLoadNotice shows it. */
export function recordRouteLoadFailure(path: string): void {
  failure.value = { path };
}

/** Hides RouteLoadNotice; nothing else changes. */
export function dismissRouteLoadFailure(): void {
  failure.value = null;
}
