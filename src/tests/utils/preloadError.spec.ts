// src/tests/utils/preloadError.spec.ts
//
// The `vite:preloadError` handler reloads through the ADR-046 forced page load
// bound instead of unconditionally: a chunk that keeps failing must not reload
// the tab in a loop.

import { loggingService } from '@/services/logging.service';
import { FORCED_RELOAD_MARKER, FORCED_RELOAD_WINDOW_MS } from '@/utils/forcedPageLoad';
import {
  handlePreloadError,
  installPreloadErrorHandler,
  wasLeftToFail,
} from '@/utils/preloadError';
import { markUnrecoverableContent } from '@/utils/unrecoverableContent';
import { beforeEach, describe, expect, it, vi } from 'vitest';

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

/** The event Vite's preload helper dispatches: cancelable, the error as payload. */
function preloadErrorEvent(message = 'Failed to fetch dynamically imported module'): Event {
  const event = new Event('vite:preloadError', { cancelable: true });
  (event as Event & { payload: Error }).payload = new Error(message);
  return event;
}

describe('handlePreloadError', () => {
  beforeEach(() => {
    sessionStorage.clear();
    vi.mocked(loggingService.error).mockClear();
    vi.mocked(loggingService.warn).mockClear();
  });

  it('reloads once and marks the event handled so the import does not reject', () => {
    const reload = vi.fn();
    const event = preloadErrorEvent();

    expect(handlePreloadError(event, { now: NOW, reload })).toBe('reloading');

    expect(reload).toHaveBeenCalledTimes(1);
    expect(event.defaultPrevented).toBe(true);
    expect(sessionStorage.getItem(FORCED_RELOAD_MARKER)).toBe(String(NOW));
    expect(loggingService.error).not.toHaveBeenCalled();
    expect(loggingService.warn).not.toHaveBeenCalled();
  });

  it('refuses a second reload within the minute, leaves the event unhandled and logs the cause', () => {
    const reload = vi.fn();
    handlePreloadError(preloadErrorEvent(), { now: NOW, reload });

    const again = preloadErrorEvent('chunk 404');
    const result = handlePreloadError(again, { now: NOW + FORCED_RELOAD_WINDOW_MS - 1, reload });

    expect(result).toBe('bounded');
    expect(reload).toHaveBeenCalledTimes(1);
    // Vite's helper rethrows the error when the event is not default-prevented,
    // so the dynamic import rejects and the router reports the failed navigation.
    expect(again.defaultPrevented).toBe(false);
    expect(loggingService.error).toHaveBeenCalledTimes(1);
    expect(vi.mocked(loggingService.error).mock.calls[0][0].message).toContain('chunk 404');
  });

  it('shares the bound with the stale-session forced page load, whatever the cause', () => {
    sessionStorage.setItem(FORCED_RELOAD_MARKER, String(NOW - 1000));
    const reload = vi.fn();
    const event = preloadErrorEvent();

    expect(handlePreloadError(event, { now: NOW, reload })).toBe('bounded');

    expect(reload).not.toHaveBeenCalled();
    expect(event.defaultPrevented).toBe(false);
  });

  it('never reloads while the page shows unrecoverable content (a revealed secret)', () => {
    const release = markUnrecoverableContent();
    const reload = vi.fn();
    const event = preloadErrorEvent('chunk 404');
    try {
      expect(handlePreloadError(event, { now: NOW, reload })).toBe('refused');

      expect(reload).not.toHaveBeenCalled();
      // Not default-prevented: the import rejects and the view's own fallback
      // (MarkdownRenderer's plain text) is what stays on screen.
      expect(event.defaultPrevented).toBe(false);
      // A refused reload does not spend the forced page load bound either.
      expect(sessionStorage.getItem(FORCED_RELOAD_MARKER)).toBeNull();
      // The refusal is the page's own decision, so it is a warning, not an
      // error that would file for every chunk the page declines to reload for.
      expect(loggingService.error).not.toHaveBeenCalled();
      expect(loggingService.warn).toHaveBeenCalledTimes(1);
      expect(vi.mocked(loggingService.warn).mock.calls[0][0]).toContain('chunk 404');
    } finally {
      release();
    }

    // Once the content is gone (the view unmounted), reloads resume.
    expect(handlePreloadError(preloadErrorEvent(), { now: NOW, reload })).toBe('reloading');
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('reloads again once the minute has passed', () => {
    const reload = vi.fn();
    handlePreloadError(preloadErrorEvent(), { now: NOW, reload });

    const result = handlePreloadError(preloadErrorEvent(), {
      now: NOW + FORCED_RELOAD_WINDOW_MS,
      reload,
    });

    expect(result).toBe('reloading');
    expect(reload).toHaveBeenCalledTimes(2);
  });
});

describe('installPreloadErrorHandler', () => {
  beforeEach(() => sessionStorage.clear());

  it('handles the event Vite dispatches on window', () => {
    const reload = vi.fn();
    installPreloadErrorHandler(window, { now: NOW, reload });

    const event = preloadErrorEvent();
    window.dispatchEvent(event);

    expect(reload).toHaveBeenCalledTimes(1);
    expect(event.defaultPrevented).toBe(true);
  });
});

describe('reloadPending', () => {
  beforeEach(() => sessionStorage.clear());

  // The flag is module state: each test imports a fresh copy.
  async function freshModule() {
    vi.resetModules();
    return import('@/utils/preloadError');
  }

  it('turns true once a failed chunk starts the reload', async () => {
    const { handlePreloadError, reloadPending } = await freshModule();
    expect(reloadPending()).toBe(false);

    handlePreloadError(preloadErrorEvent(), { now: NOW, reload: vi.fn() });

    expect(reloadPending()).toBe(true);
  });

  it('stays false when the bound refuses the reload', async () => {
    sessionStorage.setItem(FORCED_RELOAD_MARKER, String(NOW));
    const { handlePreloadError, reloadPending } = await freshModule();

    handlePreloadError(preloadErrorEvent(), { now: NOW + 1, reload: vi.fn() });

    expect(reloadPending()).toBe(false);
  });
});

// The router shows RouteLoadNotice for a navigation that fails with an import
// the handler left to fail (src/utils/routeLoadFailure.ts). It tells that
// error from any other by identity: Vite rethrows the very object it attached
// to the event.
describe('wasLeftToFail', () => {
  beforeEach(() => sessionStorage.clear());

  const payloadOf = (event: Event) => (event as Event & { payload: Error }).payload;

  it('recognises the error of an import left to fail, refused or bounded, by identity', () => {
    const release = markUnrecoverableContent();
    const refused = preloadErrorEvent('chunk 404');
    try {
      expect(handlePreloadError(refused, { now: NOW, reload: vi.fn() })).toBe('refused');
    } finally {
      release();
    }
    sessionStorage.setItem(FORCED_RELOAD_MARKER, String(NOW));
    const bounded = preloadErrorEvent('chunk 404');
    expect(handlePreloadError(bounded, { now: NOW + 1, reload: vi.fn() })).toBe('bounded');

    expect(wasLeftToFail(payloadOf(refused))).toBe(true);
    expect(wasLeftToFail(payloadOf(bounded))).toBe(true);
    // The same message on another object is another error.
    expect(wasLeftToFail(new Error('chunk 404'))).toBe(false);
  });

  it('does not recognise the error of an import that reloads, nor a non-error', () => {
    const reloading = preloadErrorEvent();
    expect(handlePreloadError(reloading, { now: NOW, reload: vi.fn() })).toBe('reloading');

    expect(wasLeftToFail(payloadOf(reloading))).toBe(false);
    expect(wasLeftToFail(undefined)).toBe(false);
    expect(wasLeftToFail('Failed to fetch dynamically imported module')).toBe(false);
  });
});
