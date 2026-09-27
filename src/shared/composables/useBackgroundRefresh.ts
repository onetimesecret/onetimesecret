// src/shared/composables/useBackgroundRefresh.ts

import { onBeforeUnmount } from 'vue';

/** How often a visible tab refreshes on its own. */
export const BACKGROUND_REFRESH_INTERVAL_MS = 5 * 60 * 1000;

/** Minimum gap between two background refreshes (rapid tab switching). */
export const BACKGROUND_REFRESH_THROTTLE_MS = 5000;

export interface BackgroundRefreshOptions {
  intervalMs?: number;
  throttleMs?: number;
}

/**
 * Keeps a list fresh while nobody is touching it: every `intervalMs` while the
 * tab is visible, and once when the tab becomes visible again. A hidden tab
 * sends nothing; the visibility change catches it up.
 *
 * Neither trigger is a person acting in the app, so `refresh` MUST make its
 * request passive (`{ passive: true }`, see src/types/declarations/axios.d.ts)
 * or the refreshes keep an unattended session alive (RISK-2026-09-19-04). The
 * callers' `refreshInBackground()` helpers do that; pass one of those, never
 * the function a button calls.
 *
 * Failures are swallowed: nobody initiated the request, so there is nothing to
 * tell them. A session that ended is handled by the API client, not here.
 *
 * Call `start()` once the initial, user-initiated load is done. Stops itself
 * when the component unmounts. Once `stop()` has run (explicitly or via
 * `onBeforeUnmount`), any subsequent `start()` is a no-op: this protects
 * callers whose `onMounted` awaits complete after the component has been
 * torn down (Vue does not await async `onMounted` before unmount).
 */
export function useBackgroundRefresh(
  refresh: () => Promise<unknown>,
  options: BackgroundRefreshOptions = {}
) {
  const intervalMs = options.intervalMs ?? BACKGROUND_REFRESH_INTERVAL_MS;
  const throttleMs = options.throttleMs ?? BACKGROUND_REFRESH_THROTTLE_MS;

  let timer: number | null = null;
  let lastRun = 0;
  // A refresh may outlast the throttle window (slow network, backpressure).
  // Without this guard a visibility-change or a second interval tick could
  // start a second request while the first is still open; if their responses
  // arrive out of order, the older one would overwrite newer data.
  let inFlight = false;
  // Once stopped (explicitly or via onBeforeUnmount), a later start() or an
  // in-flight run() continuation must not resurrect the interval/listener or
  // mutate caller state. This guards async `onMounted` callers that call
  // start() after the component has already unmounted.
  let stopped = false;

  const run = async () => {
    if (stopped) return;
    if (document.visibilityState !== 'visible') return;
    if (inFlight) return;

    const now = Date.now();
    if (now - lastRun < throttleMs) return;
    lastRun = now;

    inFlight = true;
    try {
      await refresh();
    } catch (error) {
      console.debug('[useBackgroundRefresh] refresh failed:', error);
    } finally {
      inFlight = false;
    }
  };

  const stop = () => {
    if (timer !== null) {
      window.clearInterval(timer);
      timer = null;
    }
    document.removeEventListener('visibilitychange', run);
    stopped = true;
  };

  const start = () => {
    if (stopped) return;
    // Idempotent: clear any prior interval/listener without flipping `stopped`.
    if (timer !== null) {
      window.clearInterval(timer);
      timer = null;
    }
    document.removeEventListener('visibilitychange', run);
    timer = window.setInterval(run, intervalMs);
    document.addEventListener('visibilitychange', run);
  };

  onBeforeUnmount(stop);

  return { start, stop };
}
