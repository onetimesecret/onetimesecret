// src/tests/apps/admin/useAdminDestructiveMutation.spec.ts

import { flushPromises, mount, type VueWrapper } from '@vue/test-utils';
import { AxiosError } from 'axios';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';

// One shared instance: useColonelElevation injects it once per reset, and the
// liveness examples below defer its status GET.
const mockApi = { get: vi.fn(), post: vi.fn(), delete: vi.fn() };
vi.mock('@/shared/composables/useApi', () => ({ useApi: () => mockApi }));

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
import { startElevated } from '@tests/apps/admin/support/elevation';
import { createTestI18n } from '@tests/setup';

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

const i18n = createTestI18n();

/** The composable in a bare host component (it calls useI18n); `wrapper.unmount()` disposes its scope. */
function mountHost(perform: () => Promise<unknown>): {
  mutation: UseAdminDestructiveMutation<[]>;
  wrapper: VueWrapper;
} {
  let mutation: UseAdminDestructiveMutation<[]> | undefined;
  const wrapper = mount(
    defineComponent({
      setup() {
        mutation = useAdminDestructiveMutation(perform);
        return () => null;
      },
    }),
    { global: { plugins: [i18n] } }
  );
  return { mutation: mutation!, wrapper };
}

/**
 * The composable itself, in a bare host component (it calls useI18n). The
 * view-level flows live in AdminCustomerDetailPurge.spec.ts; these pin the
 * two seams a view relies on.
 */
describe('useAdminDestructiveMutation (mounted)', () => {
  function host(perform: () => Promise<unknown>): UseAdminDestructiveMutation<[]> {
    return mountHost(perform).mutation;
  }

  beforeEach(() => __resetColonelElevationState({ statusRead: true }));
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

describe('useElevateThenOpen', () => {
  let wrapper: VueWrapper;
  let mutation: UseAdminDestructiveMutation<[]>;

  beforeEach(() => {
    __resetColonelElevationState({ statusRead: true });
    ({ mutation, wrapper } = mountHost(() => Promise.resolve()));
  });
  afterEach(() => {
    if (wrapper.exists()) wrapper.unmount();
    vi.restoreAllMocks();
    __resetColonelElevationState();
  });

  it('captures the click arguments and opens only after elevation', async () => {
    const opener = vi.fn();
    const { open, opening } = mutation.useElevateThenOpen(opener);
    const pending = open('purge', 'customer-a');
    expect(opening.value).toBe(true);
    expect(opener).not.toHaveBeenCalled();
    expect(useColonelElevation().promptOpen.value).toBe(true);

    useColonelElevation().resolvePrompt(true);
    await pending;
    expect(opener).toHaveBeenCalledExactlyOnceWith('purge', 'customer-a');
    expect(opening.value).toBe(false);
  });

  it('opens nothing on cancellation and releases the lock for another click', async () => {
    const opener = vi.fn();
    const { open, opening } = mutation.useElevateThenOpen(opener);
    const cancelled = open();
    useColonelElevation().resolvePrompt(false);
    await cancelled;
    expect(opener).not.toHaveBeenCalled();
    expect(opening.value).toBe(false);

    const next = open();
    useColonelElevation().resolvePrompt(true);
    await next;
    expect(opener).toHaveBeenCalledOnce();
  });

  it('drops repeated and competing actions while an opener awaits elevation', async () => {
    const opener = vi.fn<(verb: string, messageId: string) => void>();
    const { open } = mutation.useElevateThenOpen(opener, {
      requiresElevation: (verb: string) => verb === 'discard',
    });
    const pending = open('discard', 'message-a');
    await open('discard', 'message-b');
    await open('replay', 'message-c');
    expect(opener).not.toHaveBeenCalled();

    useColonelElevation().resolvePrompt(true);
    await pending;
    expect(opener).toHaveBeenCalledExactlyOnceWith('discard', 'message-a');
  });

  it('shares an opening lock across separate dialogs', async () => {
    const opening = ref(false);
    const firstOpener = vi.fn();
    const secondOpener = vi.fn();
    const first = mutation.useElevateThenOpen(firstOpener, { opening });
    const second = mutation.useElevateThenOpen(secondOpener, { opening });
    const pending = first.open();
    await second.open();
    useColonelElevation().resolvePrompt(true);
    await pending;
    expect(firstOpener).toHaveBeenCalledOnce();
    expect(secondOpener).not.toHaveBeenCalled();
    expect(opening.value).toBe(false);
  });

  it.each([false, true])(
    'invalidates a target that changes during elevation (restored: %s)',
    async (restore) => {
      const target = ref('customer-a');
      const opener = vi.fn();
      const { open, opening } = mutation.useElevateThenOpen(opener, { target: () => target.value });
      const pending = open();
      target.value = 'customer-b';
      if (restore) target.value = 'customer-a';
      useColonelElevation().resolvePrompt(true);
      await pending;
      expect(opener).not.toHaveBeenCalled();
      expect(opening.value).toBe(false);
    }
  );

  it('rechecks non-reactive target identity after elevation', async () => {
    let target = 'domain-a';
    const opener = vi.fn();
    const { open } = mutation.useElevateThenOpen(opener, { target: () => target });
    const pending = open();
    target = 'domain-b';
    useColonelElevation().resolvePrompt(true);
    await pending;
    expect(opener).not.toHaveBeenCalled();
  });

  it('checks eligibility before prompting and again before opening', async () => {
    const eligible = ref(false);
    const opener = vi.fn();
    const { open } = mutation.useElevateThenOpen(opener, { canOpen: () => eligible.value });
    await open();
    expect(useColonelElevation().promptOpen.value).toBe(false);

    eligible.value = true;
    const pending = open();
    eligible.value = false;
    useColonelElevation().resolvePrompt(true);
    await pending;
    expect(opener).not.toHaveBeenCalled();
  });

  it('opens lower-tier actions synchronously without elevation', async () => {
    const opener = vi.fn<(verb: string) => void>();
    const { open, opening } = mutation.useElevateThenOpen(opener, {
      requiresElevation: () => false,
    });
    const pending = open('verify');
    expect(opener).toHaveBeenCalledExactlyOnceWith('verify');
    expect(opening.value).toBe(false);
    expect(useColonelElevation().promptOpen.value).toBe(false);
    await pending;
  });

  it('does not open after unmount even if elevation was already live', async () => {
    startElevated();
    const opener = vi.fn();
    const { open, opening } = mutation.useElevateThenOpen(opener);
    const pending = open();
    wrapper.unmount();
    await pending;
    expect(opener).not.toHaveBeenCalled();
    expect(opening.value).toBe(false);
  });

  it('settles without opening when the caller unmounts under its prompt', async () => {
    const opener = vi.fn();
    const { open, opening } = mutation.useElevateThenOpen(opener);
    const pending = open();
    wrapper.unmount();
    await pending;
    expect(opener).not.toHaveBeenCalled();
    expect(opening.value).toBe(false);
    expect(useColonelElevation().promptOpen.value).toBe(false);
  });

  it('releases the lock when the opener throws', async () => {
    const opener = vi.fn().mockImplementationOnce(() => {
      throw new Error('opener failed');
    });
    const { open, opening } = mutation.useElevateThenOpen(opener, {
      requiresElevation: () => false,
    });
    await expect(open()).rejects.toThrow('opener failed');
    expect(opening.value).toBe(false);
    await open();
    expect(opener).toHaveBeenCalledTimes(2);
  });
});

/**
 * The loop lives no longer than the view that started it. `wrapper.unmount()`
 * disposes the component scope, which is the ElevationCaller the composable
 * bound its request to. Every example asserts on the retry count: the prompt
 * disappearing is not the property, the destructive verb NOT re-firing is.
 */
describe('useAdminDestructiveMutation — the caller unmounts mid-flow', () => {
  function deferred<T>() {
    let resolve!: (value: T) => void;
    let reject!: (reason?: unknown) => void;
    const promise = new Promise<T>((res, rej) => {
      resolve = res;
      reject = rej;
    });
    return { promise, resolve, reject };
  }

  const elevationRequired = () =>
    axiosError(403, { error: 'Step-up required', error_code: 'elevation_required' });

  function statusPayload(details: Record<string, unknown> = {}) {
    return {
      shrimp: '',
      record: { elevated: false, expires_at: null, seconds_remaining: 0 },
      details: {
        enabled: true,
        window: 600,
        reauth_grace: 0,
        grace_available: false,
        password_available: true,
        factors: ['password'],
        ...details,
      },
    };
  }

  beforeEach(() => {
    mockApi.get.mockReset();
    mockApi.post.mockReset();
    mockApi.delete.mockReset();
    __resetColonelElevationState({ statusRead: true });
  });
  afterEach(() => __resetColonelElevationState());

  // Scenario 1: browser-back while the request is in flight; the 403 lands on
  // a dead view. No prompt on whatever replaced it, no retry.
  it('opens no prompt and does not retry when the 403 arrives after the unmount', async () => {
    startElevated();
    const request = deferred<unknown>();
    const perform = vi.fn<() => Promise<unknown>>().mockReturnValueOnce(request.promise);
    const { mutation, wrapper } = mountHost(perform);
    const elevation = useColonelElevation();

    const running = mutation.run();
    await flushPromises();
    expect(perform).toHaveBeenCalledTimes(1);

    wrapper.unmount();
    request.reject(elevationRequired());

    await expect(running).resolves.toBe(false);
    expect(elevation.promptOpen.value).toBe(false);
    expect(perform).toHaveBeenCalledTimes(1);
    // Deliberate: the 403 is a fact about the shared session window, so the
    // locally live countdown is dropped even though this caller is gone.
    expect(elevation.elevated.value).toBe(false);
  });

  // Scenario 2: a tier-1 opener clicked before the mount-time status read
  // returned, then navigated away before it did.
  it('ensureElevated resolves false, without a prompt, when the view unmounts during the status read', async () => {
    __resetColonelElevationState();
    const read = deferred<{ data: unknown }>();
    mockApi.get.mockReturnValueOnce(read.promise);
    const { mutation, wrapper } = mountHost(() => Promise.resolve());
    const elevation = useColonelElevation();

    const pending = mutation.ensureElevated();
    await flushPromises();
    expect(mockApi.get).toHaveBeenCalledTimes(1);
    expect(elevation.promptOpen.value).toBe(false);

    wrapper.unmount();
    read.resolve({ data: statusPayload() });

    await expect(pending).resolves.toBe(false);
    expect(elevation.promptOpen.value).toBe(false);
  });

  // Scenario 3: the prompt is up for this view alone; the view goes away.
  it('closes the prompt and does not retry when the view unmounts under the open prompt', async () => {
    const perform = vi
      .fn<() => Promise<unknown>>()
      .mockRejectedValueOnce(elevationRequired())
      .mockResolvedValueOnce(undefined);
    const { mutation, wrapper } = mountHost(perform);
    const elevation = useColonelElevation();

    const running = mutation.run();
    await flushPromises();
    expect(elevation.promptOpen.value).toBe(true);
    expect(perform).toHaveBeenCalledTimes(1);

    wrapper.unmount();
    await flushPromises();

    expect(elevation.promptOpen.value).toBe(false);
    await expect(running).resolves.toBe(false);
    expect(perform).toHaveBeenCalledTimes(1);
  });

  // Scenario 5 at the mutation level: another live view keeps the prompt
  // open and the operator elevates. The dead view's retry still never fires.
  it('does not retry from a dead view even when a live co-waiter completes the prompt', async () => {
    const perform = vi
      .fn<() => Promise<unknown>>()
      .mockRejectedValueOnce(elevationRequired())
      .mockResolvedValueOnce(undefined);
    const dead = mountHost(perform);
    const live = mountHost(() => Promise.resolve());
    const elevation = useColonelElevation();

    const deadRun = dead.mutation.run();
    await flushPromises();
    expect(elevation.promptOpen.value).toBe(true);
    const liveOpen = live.mutation.ensureElevated();
    await flushPromises();

    dead.wrapper.unmount();
    await flushPromises();
    expect(elevation.promptOpen.value).toBe(true);

    elevation.resolvePrompt(true);

    await expect(liveOpen).resolves.toBe(true);
    await expect(deadRun).resolves.toBe(false);
    expect(perform).toHaveBeenCalledTimes(1);
    live.wrapper.unmount();
  });

  // The control: the same flow with the view still mounted DOES retry once.
  it('retries exactly once when the view is still mounted after the prompt', async () => {
    const perform = vi
      .fn<() => Promise<unknown>>()
      .mockRejectedValueOnce(elevationRequired())
      .mockResolvedValueOnce(undefined);
    const { mutation, wrapper } = mountHost(perform);
    const elevation = useColonelElevation();

    const running = mutation.run();
    await flushPromises();
    elevation.resolvePrompt(true);

    await expect(running).resolves.toBe(true);
    expect(perform).toHaveBeenCalledTimes(2);
    wrapper.unmount();
  });
});
