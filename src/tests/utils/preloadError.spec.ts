// src/tests/utils/preloadError.spec.ts
//
// The `vite:preloadError` handler reloads through the ADR-046 forced page load
// bound instead of unconditionally: a chunk that keeps failing must not reload
// the tab in a loop.

import { loggingService } from '@/services/logging.service';
import { FORCED_RELOAD_MARKER, FORCED_RELOAD_WINDOW_MS } from '@/utils/forcedPageLoad';
import { handlePreloadError, installPreloadErrorHandler } from '@/utils/preloadError';
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
  });

  it('reloads once and marks the event handled so the import does not reject', () => {
    const reload = vi.fn();
    const event = preloadErrorEvent();

    expect(handlePreloadError(event, { now: NOW, reload })).toBe('reloading');

    expect(reload).toHaveBeenCalledTimes(1);
    expect(event.defaultPrevented).toBe(true);
    expect(sessionStorage.getItem(FORCED_RELOAD_MARKER)).toBe(String(NOW));
    expect(loggingService.error).not.toHaveBeenCalled();
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
      expect(loggingService.error).toHaveBeenCalledTimes(1);
      expect(vi.mocked(loggingService.error).mock.calls[0][0].message).toContain('chunk 404');
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

// F24: a load that the page absorbs in place (a language switch on a page
// already showing a locale) must not reload the tab. A reload would discard
// LocaleLoadNotice and any unsaved input, and would spend the ADR-046 bound.
describe('withoutForcedReload', () => {
  beforeEach(() => sessionStorage.clear());

  // The counter and the reloading flag are module state: each test imports a
  // fresh copy, with the logger it uses.
  async function freshModules() {
    vi.resetModules();
    const preloadError = await import('@/utils/preloadError');
    const { loggingService: logger } = await import('@/services/logging.service');
    vi.mocked(logger.error).mockClear();
    return { ...preloadError, logger };
  }

  it('leaves a chunk that fails meanwhile to fail in place, and logs it', async () => {
    const { handlePreloadError, reloadPending, withoutForcedReload, logger } = await freshModules();
    const reload = vi.fn();
    const event = preloadErrorEvent('chunk bg failed');

    const result = await withoutForcedReload(async () =>
      handlePreloadError(event, { now: NOW, reload })
    );

    expect(result).toBe('in-place');
    expect(reload).not.toHaveBeenCalled();
    // Not default-prevented: Vite's helper rethrows, so the import rejects.
    expect(event.defaultPrevented).toBe(false);
    expect(reloadPending()).toBe(false);
    // The forced page load bound is not spent.
    expect(sessionStorage.getItem(FORCED_RELOAD_MARKER)).toBeNull();
    expect(logger.error).toHaveBeenCalledTimes(1);
    const message = vi.mocked(logger.error).mock.calls[0][0].message;
    expect(message).toContain('fails in place (withoutForcedReload)');
    expect(message).toContain('chunk bg failed');
  });

  it('resolves with what the load resolves and rejects with what it rejects', async () => {
    const { withoutForcedReload } = await freshModules();
    const failure = new Error('messages for bg did not load');

    await expect(withoutForcedReload(async () => 'nl')).resolves.toBe('nl');
    await expect(withoutForcedReload(() => Promise.reject(failure))).rejects.toBe(failure);
  });

  it('is released once the load resolves: the next failure reloads', async () => {
    const { handlePreloadError, withoutForcedReload } = await freshModules();
    const reload = vi.fn();

    await withoutForcedReload(async () => 'nl');

    expect(handlePreloadError(preloadErrorEvent(), { now: NOW, reload })).toBe('reloading');
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('is released once the load rejects: the next failure reloads', async () => {
    const { handlePreloadError, withoutForcedReload } = await freshModules();
    const reload = vi.fn();

    await expect(
      withoutForcedReload(() => Promise.reject(new Error('messages for bg did not load')))
    ).rejects.toThrow();

    expect(handlePreloadError(preloadErrorEvent(), { now: NOW, reload })).toBe('reloading');
  });

  it('stays in place until the outer of two nested loads settles', async () => {
    const { handlePreloadError, withoutForcedReload } = await freshModules();
    const reload = vi.fn();
    const results: string[] = [];

    await withoutForcedReload(async () => {
      await withoutForcedReload(async () => undefined);
      results.push(handlePreloadError(preloadErrorEvent(), { now: NOW, reload }));
    });
    results.push(handlePreloadError(preloadErrorEvent(), { now: NOW, reload }));

    expect(results).toEqual(['in-place', 'reloading']);
  });

  it('stays in place while any of two overlapping loads still runs', async () => {
    const { handlePreloadError, withoutForcedReload } = await freshModules();
    const reload = vi.fn();
    let finishFirst!: () => void;
    const first = withoutForcedReload(
      () => new Promise<void>((resolve) => (finishFirst = resolve))
    );
    await withoutForcedReload(async () => undefined);

    // The second load has settled; the first still runs.
    expect(handlePreloadError(preloadErrorEvent(), { now: NOW, reload })).toBe('in-place');

    finishFirst();
    await first;
    expect(handlePreloadError(preloadErrorEvent(), { now: NOW, reload })).toBe('reloading');
  });
});
