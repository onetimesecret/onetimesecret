// src/tests/utils/routeLoadFailure.spec.ts
//
// A route chunk that fails: the navigation rejects, and watchRouteLoads
// records it for RouteLoadNotice, whether the page declined to reload or
// requested a reload the user may cancel. Driven through a real router and
// the real preload handler, so the error that reaches router.onError is the
// object Vite would rethrow.

import { loggingService } from '@/services/logging.service';
import { handlePreloadError } from '@/utils/preloadError';
import {
  dismissRouteLoadFailure,
  recordRouteLoadFailure,
  routeLoadFailure,
  watchRouteLoads,
} from '@/utils/routeLoadFailure';
import { markUnrecoverableContent } from '@/utils/unrecoverableContent';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Component } from 'vue';
import { createMemoryHistory, createRouter, type Router } from 'vue-router';

vi.mock('@/services/logging.service', () => ({
  loggingService: {
    error: vi.fn(),
    warn: vi.fn(),
    info: vi.fn(),
    debug: vi.fn(),
    banner: vi.fn(),
  },
}));

const NOW = 1_800_000_000_000;
const View = { render: () => null };

/** The event Vite's preload helper dispatches for a failed chunk, with its error. */
function preloadErrorEvent(error: Error): Event {
  const event = new Event('vite:preloadError', { cancelable: true });
  (event as Event & { payload: Error }).payload = error;
  return event;
}

/** Runs the handler for `error` with a one-time value on screen: the reload is refused. */
function leaveToFail(error: Error): Error {
  const release = markUnrecoverableContent();
  try {
    const result = handlePreloadError(preloadErrorEvent(error), { now: NOW, reload: vi.fn() });
    expect(result).toBe('refused');
  } finally {
    release();
  }
  return error;
}

/** A router, watched, at '/', whose /lazy route imports its component with `load`. */
async function routerWithLazyRoute(
  load: () => Promise<Component>,
  watch: (router: Router) => void = watchRouteLoads
): Promise<Router> {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: View },
      { path: '/about', component: View },
      { path: '/lazy', component: load },
    ],
  });
  watch(router);
  await router.push('/');
  return router;
}

describe('watchRouteLoads', () => {
  beforeEach(() => {
    sessionStorage.clear();
    dismissRouteLoadFailure();
    vi.mocked(loggingService.error).mockClear();
  });

  it('records a navigation whose chunk failed with the reload declined', async () => {
    const error = leaveToFail(new TypeError('Failed to fetch dynamically imported module'));
    const router = await routerWithLazyRoute(() => Promise.reject(error));

    await expect(router.push('/lazy')).rejects.toBe(error);

    expect(routeLoadFailure.value).toEqual({ path: '/lazy' });
    // The page stays where it was; the handler already logged the chunk.
    expect(router.currentRoute.value.path).toBe('/');
    expect(loggingService.error).not.toHaveBeenCalled();
  });

  it('clears the record once a navigation completes', async () => {
    const error = leaveToFail(new TypeError('Failed to fetch dynamically imported module'));
    const router = await routerWithLazyRoute(() => Promise.reject(error));
    await router.push('/lazy').catch(() => undefined);
    expect(routeLoadFailure.value).not.toBeNull();

    await router.push('/about');

    expect(routeLoadFailure.value).toBeNull();
  });

  it('logs any other navigation error and records nothing', async () => {
    const error = new Error('the route guard threw');
    const router = await routerWithLazyRoute(() => Promise.reject(error));

    await expect(router.push('/lazy')).rejects.toBe(error);

    expect(routeLoadFailure.value).toBeNull();
    expect(loggingService.error).toHaveBeenCalledWith(error);
  });

  // The record is made before reload() is called, the ordering ADR-046
  // requires: browsers do not say whether the beforeunload prompt (unsubmitted
  // input on the page) was cancelled. The page here stays up after the
  // reload was requested, as it does after a cancelled prompt.
  it('records the navigation whose chunk failed with a reload requested, so the notice stays if the page does', async () => {
    const error = new TypeError('Failed to fetch dynamically imported module');
    const reload = vi.fn();
    expect(handlePreloadError(preloadErrorEvent(error), { now: NOW, reload })).toBe('reloading');
    expect(reload).toHaveBeenCalledTimes(1);
    const router = await routerWithLazyRoute(() => Promise.reject(error));

    await expect(router.push('/lazy')).rejects.toBe(error);

    expect(routeLoadFailure.value).toEqual({ path: '/lazy' });
    expect(router.currentRoute.value.path).toBe('/');
    // Nothing to log: the handler logs only a reload it declined.
    expect(loggingService.error).not.toHaveBeenCalled();

    // The page stayed, and errors of later navigations are still logged.
    const other = new Error('the route guard threw');
    router.addRoute({ path: '/other', component: () => Promise.reject(other) });
    await expect(router.push('/other')).rejects.toBe(other);
    expect(loggingService.error).toHaveBeenCalledWith(other);
  });
});

describe('recordRouteLoadFailure and dismissRouteLoadFailure', () => {
  it('set and clear the record RouteLoadNotice reads', () => {
    recordRouteLoadFailure('/account');
    expect(routeLoadFailure.value).toEqual({ path: '/account' });

    dismissRouteLoadFailure();
    expect(routeLoadFailure.value).toBeNull();
  });
});
