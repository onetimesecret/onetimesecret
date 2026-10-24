// src/tests/apps/admin/useColonelElevation.spec.ts

import { AxiosError } from 'axios';
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
  type ElevationCaller,
} from '@/apps/admin/composables/useColonelElevation';
import {
  ADMIN_SESSION_EXPIRED_PREFIX,
  noteAdminSessionExpiry,
} from '@/apps/admin/utils/adminSessionExpiry';
import { useAuthStore } from '@/shared/stores/authStore';

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

  // A granted window comes with a new session id, and with it a new snapshot
  // epoch (#4466, ADR-046). One auth-mutation refresh adopts it in place; the
  // next ordinary refresh would otherwise read it as a replaced session and
  // force a page load.
  it('asks the auth store for one auth-mutation snapshot after a granted window', async () => {
    const authStore = useAuthStore();
    const authRefresh = vi.spyOn(authStore, 'refresh').mockResolvedValue('applied');
    mockApi.post.mockResolvedValue({ data: grantPayload() });
    mockApi.get.mockResolvedValue({
      data: statusPayload({
        record: { elevated: true, expires_at: NOW + 600, seconds_remaining: 600 },
      }),
    });

    const elevation = useColonelElevation();
    await elevation.elevate('password', 'hunter2');

    expect(authRefresh).toHaveBeenCalledTimes(1);
    expect(authRefresh).toHaveBeenCalledWith({ kind: 'auth-mutation', reason: 'elevation' });
  });

  it('does not ask for a snapshot when the elevation fails', async () => {
    const authStore = useAuthStore();
    const authRefresh = vi.spyOn(authStore, 'refresh').mockResolvedValue('applied');
    const err = Object.assign(new Error('nope'), {
      response: { status: 403, data: { error: 'Password verification failed.' } },
    });
    mockApi.post.mockRejectedValue(err);

    const elevation = useColonelElevation();
    await elevation.elevate('password', 'wrong');

    expect(authRefresh).not.toHaveBeenCalled();
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

// The tier-1 pre-prompt seam and expired-session recovery. Same harness as above.
describe('useColonelElevation — pre-prompt and re-authentication', () => {
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

  // The tier-1 openers' guard: prove the credential BEFORE the dialog.
  describe('ensureElevated', () => {
    // A console whose mount-time status read already returned the defaults:
    // the guard decides from state, with no GET of its own. The first-read
    // examples below reset to a console that has not read its status yet.
    beforeEach(() => __resetColonelElevationState({ statusRead: true }));

    it('resolves true without prompting when step-up is disabled by config', async () => {
      mockApi.get.mockResolvedValue({ data: statusPayload({ details: { enabled: false } }) });
      const elevation = useColonelElevation();
      await elevation.refresh();

      await expect(elevation.ensureElevated()).resolves.toBe(true);
      expect(elevation.promptOpen.value).toBe(false);
    });

    it('resolves true without prompting when a window is already live', async () => {
      mockApi.get.mockResolvedValue({
        data: statusPayload({
          record: { elevated: true, expires_at: NOW + 600, seconds_remaining: 600 },
        }),
      });
      const elevation = useColonelElevation();
      await elevation.refresh();

      await expect(elevation.ensureElevated()).resolves.toBe(true);
      expect(elevation.promptOpen.value).toBe(false);
    });

    it.each([true, false])(
      'otherwise opens the prompt and resolves with the operator answer (%s)',
      async (answer) => {
        const elevation = useColonelElevation();
        const pending = elevation.ensureElevated();

        expect(elevation.promptOpen.value).toBe(true);
        elevation.resolvePrompt(answer);
        await expect(pending).resolves.toBe(answer);
        expect(elevation.promptOpen.value).toBe(false);
      }
    );

    it('makes no request of its own', async () => {
      const elevation = useColonelElevation();
      void elevation.ensureElevated();
      elevation.resolvePrompt(false);
      await vi.advanceTimersByTimeAsync(5_000);

      expect(mockApi.get).not.toHaveBeenCalled();
      expect(mockApi.post).not.toHaveBeenCalled();
    });

    // `enabled` is only a default until the first status read lands. An opener
    // clicked before the mount-time GET returns must wait for it, not decide
    // (prompt, or skip the prompt) on the default.
    it('waits for the first status read before deciding', async () => {
      __resetColonelElevationState();
      let settle!: (value: { data: unknown }) => void;
      mockApi.get.mockReturnValueOnce(
        new Promise((resolve) => {
          settle = resolve;
        })
      );
      const elevation = useColonelElevation();

      const pending = elevation.ensureElevated();
      await vi.advanceTimersByTimeAsync(0);
      expect(mockApi.get).toHaveBeenCalledTimes(1);
      expect(elevation.promptOpen.value).toBe(false);

      settle({ data: statusPayload({ details: { enabled: false } }) });
      await expect(pending).resolves.toBe(true);
      expect(elevation.promptOpen.value).toBe(false);
    });

    it('shares the mount-time status read instead of issuing its own', async () => {
      __resetColonelElevationState();
      let settle!: (value: { data: unknown }) => void;
      mockApi.get.mockReturnValueOnce(
        new Promise((resolve) => {
          settle = resolve;
        })
      );
      const elevation = useColonelElevation();

      void elevation.refresh();
      const pending = elevation.ensureElevated();
      await vi.advanceTimersByTimeAsync(0);
      expect(mockApi.get).toHaveBeenCalledTimes(1);
      expect(elevation.promptOpen.value).toBe(false);

      settle({ data: statusPayload() });
      await vi.advanceTimersByTimeAsync(0);
      expect(elevation.promptOpen.value).toBe(true);
      elevation.resolvePrompt(false);
      await expect(pending).resolves.toBe(false);
    });
  });

  // A 403 elevation_required outranks a local countdown that still reads live
  // (clock skew, a window dropped elsewhere). Without this the retry loop's
  // requestElevation() would resolve true at once and retry into the same 403.
  describe('noteElevationRequired', () => {
    it('clears a locally live window, so the next request prompts', async () => {
      mockApi.get.mockResolvedValue({
        data: statusPayload({
          record: { elevated: true, expires_at: NOW + 600, seconds_remaining: 600 },
        }),
      });
      const elevation = useColonelElevation();
      await elevation.refresh();
      const calls = mockApi.get.mock.calls.length;

      elevation.noteElevationRequired();

      expect(elevation.elevated.value).toBe(false);
      expect(elevation.expiresAt.value).toBeNull();
      expect(elevation.secondsRemaining.value).toBe(0);
      expect(mockApi.get.mock.calls.length).toBe(calls);

      void elevation.requestElevation();
      expect(elevation.promptOpen.value).toBe(true);
      elevation.resolvePrompt(false);
    });
  });

  // Recovery from an expired admin session (#4331) without leaving the page.
  describe('reauthenticate', () => {
    function reauthPayload() {
      return {
        shrimp: '',
        record: { reauthenticated: true, authenticated_at: NOW },
        details: { session_rotated: true },
      };
    }

    let reloadMock: ReturnType<typeof vi.fn>;
    const originalLocation = window.location;

    beforeEach(() => {
      reloadMock = vi.fn();
      Object.defineProperty(window, 'location', {
        value: { ...originalLocation, reload: reloadMock },
        writable: true,
        configurable: true,
      });
    });

    afterEach(() => {
      Object.defineProperty(window, 'location', {
        value: originalLocation,
        writable: true,
        configurable: true,
      });
    });

    function expire(): void {
      const error = new AxiosError('Request failed with status code 401');
      error.response = {
        status: 401,
        statusText: 'Unauthorized',
        headers: {},
        config: {} as never,
        data: {
          error: 'Authentication Required',
          message: `${ADMIN_SESSION_EXPIRED_PREFIX} Admin session idle timeout exceeded`,
        },
      };
      noteAdminSessionExpiry(error);
    }

    it('POSTs the password, clears the expired flag, adopts the session, refreshes and reloads', async () => {
      const authStore = useAuthStore();
      const authRefresh = vi.spyOn(authStore, 'refresh').mockResolvedValue('applied');
      mockApi.post.mockResolvedValue({ data: reauthPayload() });
      mockApi.get.mockResolvedValue({ data: statusPayload() });
      const elevation = useColonelElevation();
      expire();
      expect(elevation.adminSessionExpired.value).toBe(true);

      const ok = await elevation.reauthenticate('hunter2');

      expect(ok).toBe(true);
      expect(mockApi.post).toHaveBeenCalledWith('/api/colonel/reauthenticate', {
        password: 'hunter2',
      });
      expect(elevation.adminSessionExpired.value).toBe(false);
      expect(authRefresh).toHaveBeenCalledWith({ kind: 'auth-mutation', reason: 'reauth' });
      expect(mockApi.get).toHaveBeenCalledWith('/api/colonel/elevation');
      expect(reloadMock).toHaveBeenCalledTimes(1);
      expect(elevation.reauthError.value).toBeNull();
      expect(elevation.reauthLoading.value).toBe(false);
    });

    // Re-authentication renews the admin session; it is not a step-up.
    it('does not grant an elevation window', async () => {
      vi.spyOn(useAuthStore(), 'refresh').mockResolvedValue('applied');
      mockApi.post.mockResolvedValue({ data: reauthPayload() });
      mockApi.get.mockResolvedValue({ data: statusPayload() });
      const elevation = useColonelElevation();

      await elevation.reauthenticate('hunter2');

      expect(elevation.elevated.value).toBe(false);
      expect(mockApi.post).not.toHaveBeenCalledWith('/api/colonel/elevation', expect.anything());
    });

    it('reports a wrong password and changes nothing else', async () => {
      const authRefresh = vi.spyOn(useAuthStore(), 'refresh').mockResolvedValue('applied');
      const refused = new AxiosError('Request failed with status code 403');
      refused.response = {
        status: 403,
        statusText: 'Forbidden',
        headers: {},
        config: {} as never,
        data: { error: 'Password verification failed.', error_code: 'reauthentication_failed' },
      };
      mockApi.post.mockRejectedValue(refused);
      const elevation = useColonelElevation();
      expire();

      const ok = await elevation.reauthenticate('wrong');

      expect(ok).toBe(false);
      expect(elevation.reauthError.value).toBe('Password verification failed.');
      expect(elevation.reauthLoading.value).toBe(false);
      expect(elevation.adminSessionExpired.value).toBe(true);
      expect(authRefresh).not.toHaveBeenCalled();
      expect(mockApi.get).not.toHaveBeenCalled();
      expect(reloadMock).not.toHaveBeenCalled();
    });
  });
});

/**
 * A request dies with its caller, and a completion settles only the prompt
 * cycle it started in. The module-level prompt outlives any one view; without
 * these two rules a 403 arriving after browser-back would open the prompt on
 * the destination page and, once answered, retry a destructive verb from the
 * dead view. The mounted-component path is in useAdminDestructiveMutation.spec.ts;
 * these drive the seam with a hand-rolled ElevationCaller.
 */
describe('useColonelElevation — caller liveness and prompt cycle identity', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(NOW * 1000);
    __resetColonelElevationState({ statusRead: true });
  });

  afterEach(() => {
    __resetColonelElevationState();
    vi.useRealTimers();
  });

  /** An ElevationCaller the test disposes by hand, shaped like the composable's scopeCaller(). */
  function fakeCaller(): { caller: ElevationCaller; dispose: () => void } {
    let disposed = false;
    const callbacks: Array<() => void> = [];
    return {
      caller: {
        live: () => !disposed,
        onDispose: (cb) => {
          if (disposed) cb();
          else callbacks.push(cb);
        },
      },
      dispose: () => {
        disposed = true;
        for (const cb of callbacks.splice(0)) cb();
      },
    };
  }

  /** Whether `promise` has settled, after the microtask queue drains. */
  async function hasSettled(promise: Promise<unknown>): Promise<boolean> {
    let settled = false;
    void promise.then(
      () => (settled = true),
      () => (settled = true)
    );
    await vi.advanceTimersByTimeAsync(0);
    return settled;
  }

  describe('requestElevation with a caller', () => {
    it('resolves false at once for a caller already disposed, and opens no prompt', async () => {
      const elevation = useColonelElevation();
      const { caller, dispose } = fakeCaller();
      dispose();

      await expect(elevation.requestElevation(caller)).resolves.toBe(false);
      expect(elevation.promptOpen.value).toBe(false);
      expect(elevation.promptGeneration.value).toBe(0);
    });

    // Scenario 6: nobody is left to act on the answer, so the prompt closes.
    it('closes the prompt when the last live waiter is disposed', async () => {
      const elevation = useColonelElevation();
      const { caller, dispose } = fakeCaller();

      const pending = elevation.requestElevation(caller);
      expect(elevation.promptOpen.value).toBe(true);

      dispose();

      expect(elevation.promptOpen.value).toBe(false);
      await expect(pending).resolves.toBe(false);
    });

    // Scenario 5: the shared prompt stays up for the caller still mounted, and
    // the operator's go-ahead reaches ONLY that caller.
    it('keeps the prompt open for a second live waiter, who alone gets the answer', async () => {
      const elevation = useColonelElevation();
      const first = fakeCaller();
      const second = fakeCaller();

      const firstPending = elevation.requestElevation(first.caller);
      const secondPending = elevation.requestElevation(second.caller);
      expect(elevation.promptOpen.value).toBe(true);
      // One cycle, shared: the second request joined the open prompt.
      expect(elevation.promptGeneration.value).toBe(1);

      first.dispose();
      expect(elevation.promptOpen.value).toBe(true);
      expect(await hasSettled(firstPending)).toBe(false);

      elevation.resolvePrompt(true);

      await expect(secondPending).resolves.toBe(true);
      await expect(firstPending).resolves.toBe(false);
      expect(elevation.promptOpen.value).toBe(false);
    });

    // The default caller has no lifetime: it keeps the prompt open on its own
    // when a scoped co-waiter leaves.
    it('counts a caller-less request as a live waiter', async () => {
      const elevation = useColonelElevation();
      const scoped = fakeCaller();

      const bare = elevation.requestElevation();
      const scopedPending = elevation.requestElevation(scoped.caller);

      scoped.dispose();
      expect(elevation.promptOpen.value).toBe(true);

      elevation.resolvePrompt(false);
      await expect(bare).resolves.toBe(false);
      await expect(scopedPending).resolves.toBe(false);
    });

    it('resolves false for a caller disposed while the prompt was open, even on a go-ahead', async () => {
      const elevation = useColonelElevation();
      const bystander = fakeCaller();
      const leaver = fakeCaller();

      void elevation.requestElevation(bystander.caller);
      const pending = elevation.requestElevation(leaver.caller);
      leaver.dispose();

      elevation.resolvePrompt(true);
      await expect(pending).resolves.toBe(false);
    });
  });

  // Scenario 2 at the seam: the opener unmounts while the first status read
  // is still in flight. The read completes, but it must not prompt for a view
  // that is gone.
  describe('ensureElevated with a caller', () => {
    it('resolves false, without a prompt, when the caller is disposed during the status read', async () => {
      __resetColonelElevationState();
      let settle!: (value: { data: unknown }) => void;
      mockApi.get.mockReturnValueOnce(
        new Promise((resolve) => {
          settle = resolve;
        })
      );
      const elevation = useColonelElevation();
      const { caller, dispose } = fakeCaller();

      const pending = elevation.ensureElevated(caller);
      await vi.advanceTimersByTimeAsync(0);
      expect(mockApi.get).toHaveBeenCalledTimes(1);

      dispose();
      settle({ data: statusPayload() });

      await expect(pending).resolves.toBe(false);
      expect(elevation.promptOpen.value).toBe(false);
      // The read itself still landed: `enabled` is now known.
      expect(elevation.enabled.value).toBe(true);
    });

    it('resolves false at once for a caller already disposed', async () => {
      const elevation = useColonelElevation();
      const { caller, dispose } = fakeCaller();
      dispose();

      await expect(elevation.ensureElevated(caller)).resolves.toBe(false);
      expect(elevation.promptOpen.value).toBe(false);
      expect(mockApi.get).not.toHaveBeenCalled();
    });
  });

  // Scenario 4: a completion from cycle A, arriving after A was cancelled and
  // B opened, must not settle B.
  describe('resolvePrompt with a generation', () => {
    it('is a no-op while no prompt is open', async () => {
      const elevation = useColonelElevation();

      elevation.resolvePrompt(true);
      elevation.resolvePrompt(true, 0);

      expect(elevation.promptOpen.value).toBe(false);
      // The seam still works afterwards: a fresh request opens cycle 1.
      const pending = elevation.requestElevation();
      expect(elevation.promptOpen.value).toBe(true);
      expect(elevation.promptGeneration.value).toBe(1);
      elevation.resolvePrompt(false);
      await expect(pending).resolves.toBe(false);
    });

    it('ignores a stale generation and leaves the newer cycle pending', async () => {
      const elevation = useColonelElevation();

      const first = elevation.requestElevation();
      const genA = elevation.promptGeneration.value;
      elevation.resolvePrompt(false, genA);
      await expect(first).resolves.toBe(false);

      const second = elevation.requestElevation();
      const genB = elevation.promptGeneration.value;
      expect(genB).toBe(genA + 1);
      expect(elevation.promptOpen.value).toBe(true);

      // The late success of cycle A.
      elevation.resolvePrompt(true, genA);

      expect(elevation.promptOpen.value).toBe(true);
      expect(await hasSettled(second)).toBe(false);

      elevation.resolvePrompt(true, genB);
      await expect(second).resolves.toBe(true);
      expect(elevation.promptOpen.value).toBe(false);
    });

    it('ignores a stale generation after the cycle was closed by a caller disposal', async () => {
      const elevation = useColonelElevation();
      const { caller, dispose } = fakeCaller();

      const first = elevation.requestElevation(caller);
      const genA = elevation.promptGeneration.value;
      dispose();
      await expect(first).resolves.toBe(false);

      const second = elevation.requestElevation();
      elevation.resolvePrompt(true, genA);

      expect(elevation.promptOpen.value).toBe(true);
      expect(await hasSettled(second)).toBe(false);

      elevation.resolvePrompt(false);
      await expect(second).resolves.toBe(false);
    });

    it('settles the current cycle when given its own generation', async () => {
      const elevation = useColonelElevation();
      const pending = elevation.requestElevation();

      elevation.resolvePrompt(true, elevation.promptGeneration.value);

      await expect(pending).resolves.toBe(true);
      expect(elevation.promptOpen.value).toBe(false);
    });
  });
});
