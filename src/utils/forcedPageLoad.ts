// src/utils/forcedPageLoad.ts
//
// The forced page load path (ADR-046 "Forced page load", #4465).
//
// An ended session, a replaced session and a second consecutive anomaly all
// end in `window.location.reload()`. This module owns only the mechanics: the
// reload-loop bound and the reload call. The CALLER (authStore.forcePageLoad)
// must enter the stale-session state synchronously BEFORE calling in here,
// because browsers do not report whether a `beforeunload` prompt was
// cancelled: if the navigation proceeds the state is discarded with the page,
// and if the user cancels it is already on screen.
//
// Nothing here is retried. A cancelled prompt leaves the stale-session notice
// up and the user reloads when ready.

/** Per-tab marker holding the time of the last forced page-load attempt. */
export const FORCED_RELOAD_MARKER = 'ots_forced_reload_at';

/** A second forced page load inside this window is refused. */
export const FORCED_RELOAD_WINDOW_MS = 60 * 1000;

export type ForcedPageLoadResult =
  /** `reload()` was called. The page may still be here if a prompt was cancelled. */
  | 'reloading'
  /** Refused by the loop bound: stay in the stale-session state. */
  | 'bounded';

export interface ForcedPageLoadDeps {
  now?: number;
  storage?: Pick<Storage, 'getItem' | 'setItem'>;
  reload?: () => void;
}

function readMarker(storage: Pick<Storage, 'getItem'>): number | null {
  try {
    const raw = storage.getItem(FORCED_RELOAD_MARKER);
    if (raw === null) return null;
    const at = Number(raw);
    return Number.isFinite(at) ? at : null;
  } catch {
    return null;
  }
}

/**
 * Resolves the storage handle. In Safari private mode, when cookies are
 * blocked, or inside a sandboxed iframe, accessing `window.sessionStorage`
 * itself throws `SecurityError` — before any get/set call. Return `null`
 * so callers can treat the tab as unbounded and refuse the reload.
 */
function resolveStorage(deps: ForcedPageLoadDeps): Pick<Storage, 'getItem' | 'setItem'> | null {
  try {
    return deps.storage ?? window.sessionStorage;
  } catch {
    return null;
  }
}

/**
 * Reloads the page unless a forced page load was already attempted within
 * the last minute in this tab.
 *
 * The marker is written BEFORE the reload. If it cannot be written the reload
 * is refused: an unrecorded reload cannot be bounded, and the stale-session
 * notice (with its own reload button) is the safe place to stop.
 */
export function attemptForcedPageLoad(deps: ForcedPageLoadDeps = {}): ForcedPageLoadResult {
  const now = deps.now ?? Date.now();
  const storage = resolveStorage(deps);
  const reload = deps.reload ?? (() => window.location.reload());

  // No storage handle means we cannot record the marker. An unrecorded reload
  // cannot be bounded, so refuse and stay in the stale-session state.
  if (storage === null) return 'bounded';

  const last = readMarker(storage);
  // A marker from the future (clock moved back) counts as recent.
  if (last !== null && now - last < FORCED_RELOAD_WINDOW_MS) return 'bounded';

  try {
    storage.setItem(FORCED_RELOAD_MARKER, String(now));
  } catch {
    return 'bounded';
  }

  reload();
  return 'reloading';
}
