// src/utils/routeLoadFailure.ts
//
// A route whose chunk failed to load (src/utils/preloadError.ts). The
// navigation rejects and nothing renders: the URL stays, and the clicked link
// seems to do nothing. Vite's helper rethrows the error it attached to the
// event, the handler remembers it (isChunkLoadError), and the one
// router.onError below turns it into state for RouteLoadNotice, which names
// the problem and offers the manual reload that fixes a stale deployment.
//
// The record is made whether or not the handler started a reload. A reload
// that proceeds takes the record with the page; one the user cancels at the
// browser's beforeunload prompt (unsubmitted input on the page) leaves the
// notice up to explain the link, which is the ordering ADR-046 requires of
// every forced page load. The record goes away with the next navigation that
// completes, or when the notice is dismissed.
//
// Shared by both bundles' routers (src/router/index.ts and
// src/apps/admin/router.ts), which is why it lives outside src/router: the
// admin bundle must not import the customer route graph.

import { loggingService } from '@/services/logging.service';
import { isChunkLoadError } from '@/utils/preloadError';
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
 * Registers the router hooks. A navigation that fails with a chunk load error
 * is recorded; the preload handler already logged it when it declined to
 * reload. Any other navigation error is logged, as vue-router prints it itself
 * when no error handler is registered. A navigation that completes clears the
 * record.
 */
export function watchRouteLoads(router: Router): void {
  router.onError((error, to) => {
    if (isChunkLoadError(error)) {
      recordRouteLoadFailure(to.fullPath);
      return;
    }
    loggingService.error(error instanceof Error ? error : new Error(String(error)));
  });
  router.afterEach((_to, _from, navigationFailure) => {
    if (!navigationFailure) failure.value = null;
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
