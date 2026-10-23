// src/utils/preloadError.ts
//
// Recovery for a chunk that fails to load: Vite's `vite:preloadError`.
//
// With the code-split build every lazy route is a separate fetch. The common
// failure is a deployment: a tab still running the previous build asks for a
// chunk the new build replaced (build.emptyOutDir), and one reload fetches a
// shell that references the current chunks. Reloading on every failure,
// though, turns a chunk that fails persistently (a proxy or extension blocking
// the URL, a CDN that has not caught up, a CSP violation) into a reload loop:
// reload() keeps the URL, the router resolves the same route, the same fetch
// fails, and the tab reloads again. The reload therefore goes through the
// forced page load bound of ADR-046 (src/utils/forcedPageLoad.ts): one forced
// page load per tab per minute, whatever its cause.
//
// Vite's preload helper rethrows the error unless the event was
// default-prevented. A refused reload leaves the event alone, so the dynamic
// import rejects and its caller (the router) reports a failed navigation
// instead of the page reloading forever.

import { loggingService } from '@/services/logging.service';
import {
  attemptForcedPageLoad,
  type ForcedPageLoadDeps,
  type ForcedPageLoadResult,
} from '@/utils/forcedPageLoad';

/**
 * Handles one `vite:preloadError` event: reloads the page when the forced page
 * load bound allows it, otherwise logs the cause and leaves the import to fail.
 */
export function handlePreloadError(
  event: Event,
  deps: ForcedPageLoadDeps = {}
): ForcedPageLoadResult {
  const result = attemptForcedPageLoad(deps);
  if (result === 'reloading') {
    event.preventDefault();
    return result;
  }

  const cause = (event as { payload?: unknown }).payload;
  const detail = cause instanceof Error ? cause.message : String(cause);
  loggingService.error(
    new Error(
      '[preload] a chunk failed to load and the forced page load was refused ' +
        `(one per tab per minute, ADR-046); the import is left to fail: ${detail}`
    )
  );
  return result;
}

/** Installs the handler on `target`, the window by default. */
export function installPreloadErrorHandler(
  target: Window = window,
  deps: ForcedPageLoadDeps = {}
): void {
  target.addEventListener('vite:preloadError', (event) => {
    handlePreloadError(event, deps);
  });
}
