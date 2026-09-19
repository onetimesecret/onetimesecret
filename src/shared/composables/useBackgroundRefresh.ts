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
 * when the component unmounts.
 */
export function useBackgroundRefresh(
  refresh: () => Promise<unknown>,
  options: BackgroundRefreshOptions = {}
) {
  const intervalMs = options.intervalMs ?? BACKGROUND_REFRESH_INTERVAL_MS;
  const throttleMs = options.throttleMs ?? BACKGROUND_REFRESH_THROTTLE_MS;

  let timer: number | null = null;
  let lastRun = 0;

  const run = async () => {
    if (document.visibilityState !== 'visible') return;

    const now = Date.now();
    if (now - lastRun < throttleMs) return;
    lastRun = now;

    try {
      await refresh();
    } catch (error) {
      console.debug('[useBackgroundRefresh] refresh failed:', error);
    }
  };

  const stop = () => {
    if (timer !== null) {
      window.clearInterval(timer);
      timer = null;
    }
    document.removeEventListener('visibilitychange', run);
  };

  const start = () => {
    stop();
    timer = window.setInterval(run, intervalMs);
    document.addEventListener('visibilitychange', run);
  };

  onBeforeUnmount(stop);

  return { start, stop };
}
