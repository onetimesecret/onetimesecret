// src/tests/apps/admin/useAdminDestructiveMutation.spec.ts

import { flushPromises, mount } from '@vue/test-utils';
import { AxiosError } from 'axios';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent } from 'vue';

vi.mock('@/shared/composables/useApi', () => ({
  useApi: () => ({ get: vi.fn(), post: vi.fn(), delete: vi.fn() }),
}));

import {
  resolveGuardCode,
  retryAfterMinutes,
  useAdminDestructiveMutation,
  type UseAdminDestructiveMutation,
} from '@/apps/admin/composables/useAdminDestructiveMutation';
import {
  __resetColonelElevationState,
  useColonelElevation,
} from '@/apps/admin/composables/useColonelElevation';
import { createTestI18n } from '@tests/setup';
import { startElevated } from '@tests/apps/admin/support/elevation';

/**
 * The two pure resolvers behind the destructive-mutation loop.
 *
 * The composable itself is exercised end-to-end through a mounted view in
 * AdminCustomerDetailPurge.spec.ts (it calls useI18n and needs an app context);
 * these examples pin the rules that view cannot show as clearly — the precedence
 * between backend code and status family (#4327/#4329), and the rounding of the
 * operator-facing wait.
 */
function axiosError(status: number, data: unknown): AxiosError {
  const err = new AxiosError('Request failed');
  err.response = { status, data, statusText: '', headers: {}, config: {} as never };
  return err;
}

describe('resolveGuardCode', () => {
  it('reads the backend error_code first', () => {
    expect(resolveGuardCode(axiosError(403, { error_code: 'elevation_required' }))).toBe(
      'needs_elevation'
    );
    expect(resolveGuardCode(axiosError(403, { error_code: 'confirmation_required' }))).toBe(
      'needs_confirmation'
    );
    expect(resolveGuardCode(axiosError(403, { error_code: 'elevation_failed' }))).toBe(
      'elevation_failed'
    );
  });

  it('recognises a 429 by status — LimitExceeded carries no error_code', () => {
    expect(resolveGuardCode(axiosError(429, { error_type: 'LimitExceeded' }))).toBe('rate_limited');
  });

  // 403 is shared by "not a colonel", "no elevation", "wrong confirmation" and
  // "elevation attempt failed", so a status-first resolver would shadow all of
  // them. The backend code always wins where both are present.
  it('prefers the backend code over the status family', () => {
    expect(
      resolveGuardCode(
        axiosError(429, { error_code: 'elevation_required', error_type: 'LimitExceeded' })
      )
    ).toBe('needs_elevation');
  });

  it('returns null for everything else', () => {
    expect(
      resolveGuardCode(axiosError(422, { error: 'Cannot purge your own account' }))
    ).toBeNull();
    expect(resolveGuardCode(axiosError(403, { error: 'Forbidden' }))).toBeNull();
    expect(resolveGuardCode(axiosError(500, {}))).toBeNull();
    expect(resolveGuardCode(new Error('network down'))).toBeNull();
    expect(resolveGuardCode(null)).toBeNull();
  });
});

describe('retryAfterMinutes', () => {
  // Rounded UP: telling an operator to retry a second before the lockout
  // expires just spends another request on a 429.
  it('rounds partial minutes up', () => {
    expect(retryAfterMinutes(axiosError(429, { retry_after: 900 }))).toBe(15);
    expect(retryAfterMinutes(axiosError(429, { retry_after: 901 }))).toBe(16);
    expect(retryAfterMinutes(axiosError(429, { retry_after: 61 }))).toBe(2);
  });

  it('never reports less than a minute of waiting', () => {
    expect(retryAfterMinutes(axiosError(429, { retry_after: 1 }))).toBe(1);
  });

  // Null means "say nothing about the wait" — the server's own message stands
  // alone rather than the console inventing a number.
  it('is null when retry_after is absent, zero, negative or unparseable', () => {
    expect(retryAfterMinutes(axiosError(429, {}))).toBeNull();
    expect(retryAfterMinutes(axiosError(429, { retry_after: 0 }))).toBeNull();
    expect(retryAfterMinutes(axiosError(429, { retry_after: -5 }))).toBeNull();
    expect(retryAfterMinutes(axiosError(429, { retry_after: 'soon' }))).toBeNull();
    expect(retryAfterMinutes(new Error('network down'))).toBeNull();
  });
});

/**
 * The composable itself, in a bare host component (it calls useI18n). The
 * view-level flows live in AdminCustomerDetailPurge.spec.ts; these pin the
 * two seams a view relies on.
 */
describe('useAdminDestructiveMutation (mounted)', () => {
  const i18n = createTestI18n();

  function host(perform: () => Promise<unknown>): UseAdminDestructiveMutation<[]> {
    let mutation: UseAdminDestructiveMutation<[]> | undefined;
    mount(
      defineComponent({
        setup() {
          mutation = useAdminDestructiveMutation(perform);
          return () => null;
        },
      }),
      { global: { plugins: [i18n] } }
    );
    return mutation!;
  }

  beforeEach(() => __resetColonelElevationState());
  afterEach(() => __resetColonelElevationState());

  // The tier-1 opener's guard is the shared elevation one, not a copy.
  it('returns ensureElevated, which prompts when no window is live', async () => {
    const mutation = host(() => Promise.resolve());
    const elevation = useColonelElevation();

    const pending = mutation.ensureElevated();
    expect(elevation.promptOpen.value).toBe(true);

    elevation.resolvePrompt(true);
    await expect(pending).resolves.toBe(true);
  });

  // Fallback: the window lapsed server-side while the local countdown still
  // reads live. The 403 must open the prompt, not retry blind into another 403.
  it('opens the prompt on a 403 elevation_required even while a window reads live locally', async () => {
    startElevated();
    const perform = vi
      .fn<() => Promise<unknown>>()
      .mockRejectedValueOnce(
        axiosError(403, { error: 'Step-up required', error_code: 'elevation_required' })
      )
      .mockResolvedValueOnce(undefined);
    const mutation = host(perform);
    const elevation = useColonelElevation();

    const running = mutation.run();
    await flushPromises();

    expect(elevation.elevated.value).toBe(false);
    expect(elevation.promptOpen.value).toBe(true);
    expect(perform).toHaveBeenCalledTimes(1);

    elevation.resolvePrompt(true);
    await expect(running).resolves.toBe(true);
    expect(perform).toHaveBeenCalledTimes(2);
  });
});
