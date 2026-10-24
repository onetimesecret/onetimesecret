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
// shows "viewed or expired". There the view's own fallback (MarkdownRenderer
// shows the source as plain text) is the final state.
//
// A locale chunk is a chunk like any other: a language switch whose messages
// fail to load reloads the page under the same bound, and when the reload is
// refused the language store keeps the locale it shows and records the
// failure for LocaleLoadNotice (src/shared/stores/languageStore.ts).
//
// The import is left to fail in every case, reload or not. Vite's preload
// helper rethrows the error unless the event is default-prevented, and this
// handler never prevents it, so the dynamic import rejects with the error Vite
// attached to the event and its caller (the router, a component) fails as it
// would for any load error. The handler remembers that error
// (isChunkLoadError), so the router can tell a route chunk that failed from
// any other navigation error and record it for RouteLoadNotice, with a manual
// reload button (src/utils/routeLoadFailure.ts); a component that imports a
// chunk itself renders its own fallback.
//
// The failure is on record before reload() is called, which is the order
// ADR-046 requires of every forced page load: browsers do not report whether
// a `beforeunload` prompt was cancelled. When the reload proceeds, the page
// and its record go together; when the user keeps the page (unsubmitted
// input, the prompt dismissed), the notice stays up and explains the link
// that did nothing. Nothing is retried.
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

// Set once a failed chunk has made this page call reload(). See reloadPending.
let reloading = false;

// The errors of failed chunks, as Vite attached them to the event and
// rethrows them to the import's caller. See isChunkLoadError.
const chunkErrors = new WeakSet<object>();

/**
 * Handles one `vite:preloadError` event: records the failure, then reloads
 * the page when nothing on it would be lost and the forced page load bound
 * allows it, otherwise logs the cause. The import fails either way.
 */
export function handlePreloadError(
  event: Event,
  deps: ForcedPageLoadDeps = {}
): ForcedPageLoadResult {
  const cause = (event as { payload?: unknown }).payload;
  if (typeof cause === 'object' && cause !== null) chunkErrors.add(cause);

  const result = attemptForcedPageLoad(deps);
  if (result === 'reloading') {
    reloading = true;
    return result;
  }

  const why = {
    refused: 'the page shows content a reload would destroy',
    bounded: 'the forced page load was refused (one per tab per minute, ADR-046)',
  }[result];
  const message =
    `[preload] a chunk failed to load and ${why}; the import is left to fail: ` +
    describeCause(event);
  // A refusal is the page's own decision, taken because the fallback costs
  // less than a reload; a chunk that fails again inside the bound's window,
  // with a reload already spent, is the page's error.
  if (result === 'bounded') loggingService.error(new Error(message));
  else loggingService.warn(message);
  return result;
}

/**
 * True once a failed chunk has started this page's reload. The import that
 * failed rejects, so its caller fails on it: an initial navigation whose route
 * component did not load fails, and one whose locale did not load resolves in
 * a fallback locale. startApp leaves the shell to the reload in both cases,
 * neither flagging a failure nor mounting a page the reload is about to
 * replace. Never cleared: a cancelled `beforeunload` prompt leaves the page
 * up with this still true, which is why nothing but startApp's one-time
 * decision depends on it.
 */
export function reloadPending(): boolean {
  return reloading;
}

/**
 * Whether `error` is the rejection of an import whose chunk failed to load,
 * whether or not the page is reloading for it. The router records a
 * navigation that fails with such an error for RouteLoadNotice
 * (src/utils/routeLoadFailure.ts); any other error of a navigation is not a
 * failed chunk.
 */
export function isChunkLoadError(error: unknown): boolean {
  return typeof error === 'object' && error !== null && chunkErrors.has(error);
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
