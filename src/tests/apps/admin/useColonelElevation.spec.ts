// src/tests/apps/admin/useColonelElevation.spec.ts

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * The step-up (sudo) composable (#4327).
 *
 * The load-bearing assertion in this file is the one about CALL COUNTS: the
 * countdown must advance with ZERO additional HTTP. `TrackMetadata` advances a
 * session's `last_activity_at` on every authenticated request, so a banner that
 * polled GET /api/colonel/elevation would re-stamp it forever and make the admin
 * idle timeout (#4331) unreachable while a tab is open. A timer here is not a
 * performance question, it disables a shipped security control.
 *
 * The rest pins the fetch triggers the design allows: mount, after elevate,
 * after drop, and (exercised in AdminCustomerDetailPurge.spec.ts) on a 403.
 */

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

import {
  __resetColonelElevationState,
  useColonelElevation,
} from '@/apps/admin/composables/useColonelElevation';

const NOW = 1_700_000_000;

function statusPayload(overrides: Record<string, unknown> = {}) {
  return {
    shrimp: '',
    record: { elevated: false, expires_at: null, seconds_remaining: 0, ...(overrides.record ?? {}) },
    details: {
      enabled: true,
      window: 600,
      reauth_grace: 0,
      grace_available: false,
      password_available: true,
      factors: ['password'],
      ...(overrides.details ?? {}),
    },
  };
}

function grantPayload(factor = 'password') {
  return {
    shrimp: '',
    record: { elevated: true, expires_at: NOW + 600, seconds_remaining: 600 },
    details: { factor, window: 600 },
  };
}

describe('useColonelElevation', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(NOW * 1000);
    __resetColonelElevationState();
  });

  afterEach(() => {
    __resetColonelElevationState();
    vi.useRealTimers();
  });

  it('reads status on refresh and reports the un-elevated default', async () => {
    mockApi.get.mockResolvedValue({ data: statusPayload() });

    const elevation = useColonelElevation();
    await elevation.refresh();

    expect(mockApi.get).toHaveBeenCalledTimes(1);
    expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/elevation');
    expect(elevation.elevated.value).toBe(false);
    expect(elevation.enabled.value).toBe(true);
    expect(elevation.window.value).toBe(600);
    expect(elevation.factors.value).toEqual(['password']);
  });

  it('surfaces a live window with a countdown seed', async () => {
    mockApi.get.mockResolvedValue({
      data: statusPayload({
        record: { elevated: true, expires_at: NOW + 420, seconds_remaining: 420 },
      }),
    });

    const elevation = useColonelElevation();
    await elevation.refresh();

    expect(elevation.elevated.value).toBe(true);
    expect(elevation.secondsRemaining.value).toBe(420);
  });

  // THE regression guard for the "do not poll" property.
  it('counts down with ZERO additional HTTP calls', async () => {
    mockApi.get.mockResolvedValue({
      data: statusPayload({
        record: { elevated: true, expires_at: NOW + 30, seconds_remaining: 30 },
      }),
    });

    const elevation = useColonelElevation();
    await elevation.refresh();
    const callsAfterRefresh = mockApi.get.mock.calls.length;

    // advanceTimersByTime moves the faked clock too, so Date.now() and the
    // interval stay in step — exactly what the countdown reads.
    await vi.advanceTimersByTimeAsync(10_000);

    expect(elevation.secondsRemaining.value).toBe(20);
    expect(mockApi.get.mock.calls.length).toBe(callsAfterRefresh);
    expect(mockApi.post).not.toHaveBeenCalled();
    expect(mockApi.delete).not.toHaveBeenCalled();
  });

  it('flips to un-elevated locally when the window runs out, still with no HTTP', async () => {
    mockApi.get.mockResolvedValue({
      data: statusPayload({
        record: { elevated: true, expires_at: NOW + 3, seconds_remaining: 3 },
      }),
    });

    const elevation = useColonelElevation();
    await elevation.refresh();
    const callsAfterRefresh = mockApi.get.mock.calls.length;

    await vi.advanceTimersByTimeAsync(5_000);

    expect(elevation.elevated.value).toBe(false);
    expect(elevation.secondsRemaining.value).toBe(0);
    expect(mockApi.get.mock.calls.length).toBe(callsAfterRefresh);
  });

  it('POSTs the factor and password, then refreshes once', async () => {
    mockApi.post.mockResolvedValue({ data: grantPayload() });
    mockApi.get.mockResolvedValue({
      data: statusPayload({
        record: { elevated: true, expires_at: NOW + 600, seconds_remaining: 600 },
      }),
    });

    const elevation = useColonelElevation();
    const ok = await elevation.elevate('password', 'hunter2');

    expect(ok).toBe(true);
    expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/elevation', {
      factor: 'password',
      password: 'hunter2',
    });
    expect(mockApi.get).toHaveBeenCalledTimes(1);
    expect(elevation.elevated.value).toBe(true);
    expect(elevation.activeFactor.value).toBe('password');
  });

  // The weaker path must stay visible while it is live (review B-3.4).
  it('carries the recent_auth factor back so the banner can label it', async () => {
    mockApi.post.mockResolvedValue({ data: grantPayload('recent_auth') });
    mockApi.get.mockResolvedValue({
      data: statusPayload({
        record: { elevated: true, expires_at: NOW + 600, seconds_remaining: 600 },
      }),
    });

    const elevation = useColonelElevation();
    await elevation.elevate('recent_auth');

    expect(elevation.activeFactor.value).toBe('recent_auth');
  });

  it('reports a failed elevation without granting anything', async () => {
    const err = Object.assign(new Error('nope'), {
      response: { status: 403, data: { error: 'Password verification failed.' } },
    });
    mockApi.post.mockRejectedValue(err);

    const elevation = useColonelElevation();
    const ok = await elevation.elevate('password', 'wrong');

    expect(ok).toBe(false);
    expect(elevation.elevated.value).toBe(false);
    // No refresh on the failure path — nothing changed server-side.
    expect(mockApi.get).not.toHaveBeenCalled();
  });

  it('DELETEs on drop and lands un-elevated', async () => {
    mockApi.delete.mockResolvedValue({ data: {} });
    mockApi.get.mockResolvedValue({ data: statusPayload() });

    const elevation = useColonelElevation();
    const ok = await elevation.drop();

    expect(ok).toBe(true);
    expect(mockApi.delete).toHaveBeenCalledWith('/api/colonel/elevation');
    expect(mockApi.get).toHaveBeenCalledTimes(1);
    expect(elevation.elevated.value).toBe(false);
  });

  describe('requestElevation', () => {
    it('resolves immediately when a window is already live, without prompting', async () => {
      mockApi.get.mockResolvedValue({
        data: statusPayload({
          record: { elevated: true, expires_at: NOW + 600, seconds_remaining: 600 },
        }),
      });
      const elevation = useColonelElevation();
      await elevation.refresh();

      await expect(elevation.requestElevation()).resolves.toBe(true);
      expect(elevation.promptOpen.value).toBe(false);
    });

    it('opens the prompt and waits for the operator', async () => {
      const elevation = useColonelElevation();
      const pending = elevation.requestElevation();

      expect(elevation.promptOpen.value).toBe(true);

      elevation.resolvePrompt(true);
      await expect(pending).resolves.toBe(true);
      expect(elevation.promptOpen.value).toBe(false);
    });

    it('resolves false when the operator cancels', async () => {
      const elevation = useColonelElevation();
      const pending = elevation.requestElevation();

      elevation.resolvePrompt(false);
      await expect(pending).resolves.toBe(false);
    });
  });

  describe('unsatisfiable', () => {
    it('is false for an ordinary password-holding account', async () => {
      mockApi.get.mockResolvedValue({ data: statusPayload() });
      const elevation = useColonelElevation();
      await elevation.refresh();

      expect(elevation.unsatisfiable.value).toBe(false);
    });

    it('is true for an SSO-only account with no grace configured', async () => {
      mockApi.get.mockResolvedValue({
        data: statusPayload({
          details: { password_available: false, factors: ['password'] },
        }),
      });
      const elevation = useColonelElevation();
      await elevation.refresh();

      expect(elevation.unsatisfiable.value).toBe(true);
    });

    it('is false once a grace makes recent_auth available', async () => {
      mockApi.get.mockResolvedValue({
        data: statusPayload({
          details: {
            password_available: false,
            reauth_grace: 300,
            grace_available: true,
            factors: ['password', 'recent_auth'],
          },
        }),
      });
      const elevation = useColonelElevation();
      await elevation.refresh();

      expect(elevation.unsatisfiable.value).toBe(false);
    });
  });
});
