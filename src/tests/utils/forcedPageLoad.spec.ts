// src/tests/utils/forcedPageLoad.spec.ts
//
// ADR-046 "Forced page load": the reload-loop bound (#4465).

import {
  attemptForcedPageLoad,
  FORCED_RELOAD_MARKER,
  FORCED_RELOAD_WINDOW_MS,
} from '@/utils/forcedPageLoad';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const NOW = 1_800_000_000_000;

describe('attemptForcedPageLoad', () => {
  beforeEach(() => sessionStorage.clear());

  it('records the attempt in per-tab storage BEFORE reloading', () => {
    let markerAtReload: string | null = null;
    const reload = vi.fn(() => {
      markerAtReload = sessionStorage.getItem(FORCED_RELOAD_MARKER);
    });

    expect(attemptForcedPageLoad({ now: NOW, reload })).toBe('reloading');

    expect(reload).toHaveBeenCalledTimes(1);
    expect(markerAtReload).toBe(String(NOW));
  });

  it('refuses a second forced page load within one minute, whatever its cause', () => {
    const reload = vi.fn();
    attemptForcedPageLoad({ now: NOW, reload });

    expect(attemptForcedPageLoad({ now: NOW + FORCED_RELOAD_WINDOW_MS - 1, reload })).toBe('bounded');

    expect(reload).toHaveBeenCalledTimes(1);
    // A refused attempt does not extend the window.
    expect(sessionStorage.getItem(FORCED_RELOAD_MARKER)).toBe(String(NOW));
  });

  it('allows one again once the minute has passed', () => {
    const reload = vi.fn();
    attemptForcedPageLoad({ now: NOW, reload });

    expect(attemptForcedPageLoad({ now: NOW + FORCED_RELOAD_WINDOW_MS, reload })).toBe('reloading');
    expect(reload).toHaveBeenCalledTimes(2);
  });

  it('treats a marker from the future (clock moved back) as recent', () => {
    sessionStorage.setItem(FORCED_RELOAD_MARKER, String(NOW + 10 * FORCED_RELOAD_WINDOW_MS));
    const reload = vi.fn();

    expect(attemptForcedPageLoad({ now: NOW, reload })).toBe('bounded');
    expect(reload).not.toHaveBeenCalled();
  });

  it('ignores an unreadable marker', () => {
    sessionStorage.setItem(FORCED_RELOAD_MARKER, 'not-a-time');
    const reload = vi.fn();

    expect(attemptForcedPageLoad({ now: NOW, reload })).toBe('reloading');
  });

  it('does not reload when the attempt cannot be recorded: an unrecorded reload cannot be bounded', () => {
    const reload = vi.fn();
    const storage = {
      getItem: () => null,
      setItem: () => {
        throw new DOMException('denied', 'SecurityError');
      },
    };

    expect(attemptForcedPageLoad({ now: NOW, storage, reload })).toBe('bounded');
    expect(reload).not.toHaveBeenCalled();
  });

  it('never calls reload more than once per call, and schedules nothing', () => {
    vi.useFakeTimers();
    const reload = vi.fn();

    attemptForcedPageLoad({ now: NOW, reload });
    vi.advanceTimersByTime(10 * FORCED_RELOAD_WINDOW_MS);

    expect(reload).toHaveBeenCalledTimes(1);
    expect(vi.getTimerCount()).toBe(0);
    vi.useRealTimers();
  });
});
