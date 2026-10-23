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
// attemptForcedPageLoad also refuses while the page shows content a reload
// would destroy (src/utils/unrecoverableContent.ts): a revealed secret exists
// only in the tab once the reveal request has run, and a reload of that page
// shows "viewed or expired". There the import is left to fail, and the view's
// own fallback (MarkdownRenderer shows the source as plain text) is the final
// state.
//
// Vite's preload helper rethrows the error unless the event was
// default-prevented. A refused reload leaves the event alone, so the dynamic
// import rejects and its caller (the router, a component) reports the failure
// instead of the page reloading.
//
// Only dynamic imports reach this handler: Vite dispatches the event from its
// preload helper. A chunk of the entry's static import graph that fails to
// load (deploy skew between containers) fails the entry itself, before any of
// this runs; the server shell's stalled-load notice with its manual reload
// link (#4596) is the backstop there.

import { loggingService } from '@/services/logging.service';
import {
  attemptForcedPageLoad,
  type ForcedPageLoadDeps,
  type ForcedPageLoadResult,
} from '@/utils/forcedPageLoad';

/**
 * Handles one `vite:preloadError` event: reloads the page when nothing on it
 * would be lost and the forced page load bound allows it, otherwise logs the
 * cause and leaves the import to fail.
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

  const why =
    result === 'refused'
      ? 'the page shows content a reload would destroy'
      : 'the forced page load was refused (one per tab per minute, ADR-046)';
  loggingService.error(
    new Error(
      `[preload] a chunk failed to load and ${why}; the import is left to fail: ` +
        describeCause(event)
    )
  );
  return result;
}

/** The error Vite's helper attached to the event, as text. */
function describeCause(event: Event): string {
  const cause = (event as { payload?: unknown }).payload;
  return cause instanceof Error ? cause.message : String(cause);
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
