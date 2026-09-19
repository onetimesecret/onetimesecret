// src/tests/stores/authStore.coordinator.spec.ts
//
// #4459: one refresh coordinator (ADR-046, "Refresh coordination").

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { _resetForTesting } from '@/services/bootstrap.service';
import {
  AUTH_CHECK_CONFIG,
  parseRetryAfter,
  retryDelay,
  useAuthStore,
} from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import {
  anonymousBootstrap,
  authenticatedBootstrap,
  inOtherEpoch,
  mfaPendingBootstrap,
  mockCustomer,
  newerSnapshot,
  unavailableBootstrap,
} from '@/tests/fixtures/bootstrap.fixture';
import { toWire } from '@/tests/fixtures/bootstrap-wire';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { getActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';

const ENDPOINT = AUTH_CHECK_CONFIG.ENDPOINT;
const BOOTSTRAP_KEY = '__BOOTSTRAP_ME__';

type Reply = [number, unknown?, Record<string, string>?];

// Another account is another session: its snapshots start a new epoch.
const accountB: BootstrapPayload = {
  ...inOtherEpoch(authenticatedBootstrap),
  cust: { ...mockCustomer, objid: 'cust-b', extid: 'ur-b', email: 'b@example.com' },
  custid: 'ur-b',
  email: 'b@example.com',
};

// The forced page load path is covered in authStore.acceptance.spec.ts; here
// it must only never reach jsdom's unimplemented navigation.
vi.mock('@/utils/forcedPageLoad', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/utils/forcedPageLoad')>()),
  attemptForcedPageLoad: vi.fn(() => 'reloading'),
}));

/**
 * The wire form of the NEXT snapshot in the stream. A refresh response must be
 * strictly newer than what the tab holds, or it is an anomaly (ADR-046).
 */
let tick = 0;
const next = (payload: BootstrapPayload) => toWire(newerSnapshot(payload, ++tick));

/** A reply the test resolves by hand, to control the order responses land in. */
function deferred() {
  let resolve!: (reply: Reply) => void;
  const promise = new Promise<Reply>((r) => (resolve = r));
  return { promise, resolve };
}

describe('authStore refresh coordinator (#4459)', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useAuthStore>;
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  async function mountWith(hydration: BootstrapPayload | null) {
    _resetForTesting();
    const win = window as unknown as Record<string, unknown>;
    if (hydration) win[BOOTSTRAP_KEY] = toWire(hydration);
    else delete win[BOOTSTRAP_KEY];

    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock as AxiosMockAdapter;
    bootstrapStore = useBootstrapStore();
    store = useAuthStore();
    // autoInitPlugin does not fire under createTestingPinia in this harness;
    // like the other store specs, initialize explicitly, in app order.
    // Fake timers BEFORE init: init schedules the passive interval.
    vi.useFakeTimers();
    bootstrapStore.init();
    store.init();
  }

  const requests = () => axiosMock.history.get.filter((r) => r.url === ENDPOINT).length;

  beforeEach(() => {
    vi.spyOn(Math, 'random').mockReturnValue(0.5);
  });

  afterEach(() => {
    store?.$dispose();
    axiosMock?.restore();
    vi.useRealTimers();
    vi.restoreAllMocks();
    _resetForTesting();
    delete (window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY];
    sessionStorage.clear();
  });

  describe('hydration is the initial snapshot (#4456)', () => {
    it('a valid hydrated page makes no startup request', async () => {
      await mountWith(authenticatedBootstrap);

      expect(store.authStatus).toBe('authenticated');
      expect(store.isAuthenticated).toBe(true);
      expect(requests()).toBe(0);
    });

    it('missing hydration is `checking`; one failed verification is `unavailable`, not anonymous', async () => {
      await mountWith(null);
      expect(store.authStatus).toBe('checking');
      axiosMock.onGet(ENDPOINT).networkError();

      expect(await store.refresh({ kind: 'ordinary', reason: 'initial-verification' })).toBe('failed');

      expect(store.authStatus).toBe('unavailable');
    });

    it('missing hydration becomes whatever the server then says', async () => {
      await mountWith(null);
      axiosMock.onGet(ENDPOINT).reply(() => [200, next(authenticatedBootstrap)]);

      expect(await store.refresh({ kind: 'ordinary', reason: 'initial-verification' })).toBe('applied');

      expect(store.authStatus).toBe('authenticated');
      expect(bootstrapStore.cust?.extid).toBe(mockCustomer.extid);
    });
  });

  describe('deduplication', () => {
    it('concurrent ordinary requests share one request', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(() => [200, next(authenticatedBootstrap)]);

      const outcomes = await Promise.all([
        store.refresh({ kind: 'ordinary', reason: 'visibility' }),
        store.refresh({ kind: 'ordinary', reason: 'interval' }),
        store.checkWindowStatus(),
        store.refreshAuthState(),
      ]);

      expect(requests()).toBe(1);
      expect(outcomes.slice(0, 2)).toEqual(['applied', 'applied']);
    });

    it('an ordinary request joins an authentication mutation already in flight', async () => {
      await mountWith(anonymousBootstrap);
      axiosMock.onGet(ENDPOINT).reply(() => [200, next(authenticatedBootstrap)]);

      await Promise.all([store.setAuthenticated(true), store.refresh({ kind: 'ordinary', reason: 'csrf' })]);

      expect(requests()).toBe(1);
    });
  });

  describe('generations', () => {
    it('a response that started before a local sign-out never restores identity', async () => {
      await mountWith(authenticatedBootstrap);
      const late = deferred();
      axiosMock.onGet(ENDPOINT).replyOnce(() => late.promise);

      const pending = store.refresh({ kind: 'ordinary', reason: 'interval' });
      await store.logout();
      late.resolve([200, next(authenticatedBootstrap)]);

      expect(await pending).toBe('superseded');
      expect(store.authStatus).toBe('anonymous');
      expect(bootstrapStore.cust).toBeNull();
    });

    it('an older response never restores identity after a later rejection', async () => {
      await mountWith(authenticatedBootstrap);
      const older = deferred();
      const newer = deferred();
      axiosMock.onGet(ENDPOINT).replyOnce(() => older.promise).onGet(ENDPOINT).replyOnce(() => newer.promise);

      const first = store.refresh({ kind: 'ordinary', reason: 'interval' });
      const second = store.refresh({ kind: 'auth-mutation', reason: 'login' });
      expect(requests()).toBe(2);

      // The newer request learns of the rejection first...
      newer.resolve([200, toWire(anonymousBootstrap)]);
      expect(await second).toBe('applied');
      // ...and the older one, still saying "authenticated", lands afterwards.
      older.resolve([200, next(authenticatedBootstrap)]);
      expect(await first).toBe('superseded');

      expect(store.authStatus).toBe('anonymous');
      expect(bootstrapStore.cust).toBeNull();
    });

    it('reverse resolution order keeps the newest generation too', async () => {
      await mountWith(anonymousBootstrap);
      const older = deferred();
      const newer = deferred();
      axiosMock.onGet(ENDPOINT).replyOnce(() => older.promise).onGet(ENDPOINT).replyOnce(() => newer.promise);

      const first = store.refresh({ kind: 'ordinary', reason: 'csrf' });
      const second = store.refresh({ kind: 'auth-mutation', reason: 'login' });

      older.resolve([200, toWire(anonymousBootstrap)]);
      expect(await first).toBe('superseded');
      expect(store.authStatus).toBe('anonymous');

      newer.resolve([200, toWire(accountB)]);
      expect(await second).toBe('applied');
      expect(bootstrapStore.custid).toBe('ur-b');
    });

    it('a superseded FAILURE counts for nothing either', async () => {
      await mountWith(authenticatedBootstrap);
      const older = deferred();
      axiosMock.onGet(ENDPOINT).replyOnce(() => older.promise).onGet(ENDPOINT).reply(() => [200, next(authenticatedBootstrap)]);

      const first = store.refresh({ kind: 'ordinary', reason: 'interval' });
      await store.refresh({ kind: 'auth-mutation', reason: 'mfa' });
      older.resolve([500]);

      expect(await first).toBe('superseded');
      expect(store.failureCount).toBe(0);
    });
  });

  describe('authentication mutations ask the server', () => {
    it('setAuthenticated(true) sets nothing locally: the answer is the state', async () => {
      await mountWith(anonymousBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(mfaPendingBootstrap));

      await store.setAuthenticated(true);

      expect(requests()).toBe(1);
      expect(store.isAuthenticated).toBe(false);
      expect(store.awaitingMfa).toBe(true);
      expect(sessionStorage.getItem('ots_auth_state')).toBeNull();
    });

    it('an account change resets the account-scoped stores that exist', async () => {
      await mountWith(authenticatedBootstrap);
      const organizationStore = useOrganizationStore();
      const reset = vi.spyOn(organizationStore, '$reset');
      const created = () => Object.keys(getActivePinia()?.state.value ?? {});
      const before = created();
      axiosMock.onGet(ENDPOINT).reply(200, toWire(accountB));

      await store.refresh({ kind: 'auth-mutation', reason: 'account-switch' });

      expect(bootstrapStore.custid).toBe('ur-b');
      expect(reset).toHaveBeenCalledTimes(1);
      // Stores that were never created are not created just to be reset.
      expect(created()).toEqual(before);
    });

    it('the same account refreshing resets nothing', async () => {
      await mountWith(authenticatedBootstrap);
      const reset = vi.spyOn(useOrganizationStore(), '$reset');
      axiosMock.onGet(ENDPOINT).reply(() => [200, next(authenticatedBootstrap)]);

      await store.refresh({ kind: 'ordinary', reason: 'interval' });

      expect(reset).not.toHaveBeenCalled();
    });

    it("losing authority through this tab's own mutation resets them", async () => {
      await mountWith(authenticatedBootstrap);
      const reset = vi.spyOn(useOrganizationStore(), '$reset');
      axiosMock.onGet(ENDPOINT).reply(200, toWire(anonymousBootstrap));

      await store.refresh({ kind: 'auth-mutation', reason: 'check' });

      expect(store.authStatus).toBe('anonymous');
      expect(reset).toHaveBeenCalledTimes(1);
    });
  });

  describe('a failure mutates nothing', () => {
    const failures: Array<[string, (mock: AxiosMockAdapter) => void]> = [
      ['a network error', (mock) => mock.onGet(ENDPOINT).networkError()],
      ['a timeout', (mock) => mock.onGet(ENDPOINT).timeout()],
      ['a 500', (mock) => mock.onGet(ENDPOINT).reply(500)],
      ['a 503 (snapshot ordering unavailable)', (mock) => mock.onGet(ENDPOINT).reply(503, { error: 'x' }, { 'retry-after': '5' })],
      ['a payload that fails the contract', (mock) => mock.onGet(ENDPOINT).reply(200, { ...toWire(authenticatedBootstrap), shrimp: 42 })],
      ['a snapshot that says `unavailable`', (mock) => mock.onGet(ENDPOINT).reply(200, toWire(unavailableBootstrap))],
    ];

    it.each(failures)('%s', async (_name, arrange) => {
      await mountWith(authenticatedBootstrap);
      const before = JSON.stringify(bootstrapStore.$state);
      arrange(axiosMock);

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('failed');

      expect(JSON.stringify(bootstrapStore.$state)).toBe(before);
      expect(store.authStatus).toBe('authenticated');
      expect(store.failureCount).toBe(1);
    });

    it('repeated failures become `unavailable`, never a sign-out', async () => {
      await mountWith(authenticatedBootstrap);
      sessionStorage.setItem('unrelated', 'kept');
      axiosMock.onGet(ENDPOINT).reply(500);

      for (let i = 0; i < 100; i++) await store.retryNow();

      expect(store.authStatus).toBe('unavailable');
      expect(store.isAuthenticated).toBe(false);
      // The last accepted snapshot stands: nothing was logged out or cleared.
      expect(bootstrapStore.cust?.extid).toBe(mockCustomer.extid);
      expect(sessionStorage.getItem('unrelated')).toBe('kept');
    });

    it('becomes `unavailable` exactly at MAX_FAILURES', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(500);

      for (let i = 1; i < AUTH_CHECK_CONFIG.MAX_FAILURES; i++) {
        await store.retryNow();
        expect(store.authStatus).toBe('authenticated');
      }
      await store.retryNow();
      expect(store.authStatus).toBe('unavailable');
    });

    it('the first success after failures applies the server state', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(500);
      for (let i = 0; i < 5; i++) await store.retryNow();
      expect(store.authStatus).toBe('unavailable');

      axiosMock.reset();
      axiosMock.onGet(ENDPOINT).reply(() => [200, next(authenticatedBootstrap)]);
      expect(await store.retryNow()).toBe('applied');

      expect(store.authStatus).toBe('authenticated');
      expect(store.failureCount).toBe(0);
    });
  });

  describe('backoff', () => {
    it('stays within [floor, cap] for any failure count and any draw', () => {
      for (const draw of [0, 0.25, 0.5, 0.999999]) {
        for (let failures = 1; failures <= 64; failures++) {
          const delay = retryDelay(failures, 0, () => draw);
          expect(delay).toBeGreaterThanOrEqual(AUTH_CHECK_CONFIG.BACKOFF_FLOOR);
          expect(delay).toBeLessThanOrEqual(AUTH_CHECK_CONFIG.BACKOFF_CAP);
        }
      }
    });

    it('grows exponentially up to the cap', () => {
      const ceiling = (failures: number) => retryDelay(failures, 0, () => 0.999999);
      expect(Math.round(ceiling(1))).toBe(2000);
      expect(Math.round(ceiling(2))).toBe(4000);
      expect(Math.round(ceiling(3))).toBe(8000);
      expect(Math.round(ceiling(10))).toBe(60000);
    });

    it('is jittered: the draw decides the delay', () => {
      expect(retryDelay(4, 0, () => 0.25)).toBe(4000);
      expect(retryDelay(4, 0, () => 0.75)).toBe(12000);
    });

    it('never retries sooner than Retry-After', () => {
      expect(retryDelay(1, 5000, () => 0)).toBe(5000);
      expect(retryDelay(1, 5000, () => 0.999999)).toBe(5000);
    });

    it('parses Retry-After as seconds or an HTTP-date, capped', () => {
      const now = Date.parse('2026-09-19T00:00:00Z');
      expect(parseRetryAfter('5')).toBe(5000);
      expect(parseRetryAfter(7)).toBe(7000);
      expect(parseRetryAfter('Sat, 19 Sep 2026 00:00:30 GMT', now)).toBe(30000);
      expect(parseRetryAfter('86400')).toBe(AUTH_CHECK_CONFIG.RETRY_AFTER_CAP);
      for (const useless of [undefined, null, '', 'soon', '-3', 'Sat, 19 Sep 2020 00:00:00 GMT']) {
        expect(parseRetryAfter(useless, now)).toBe(0);
      }
    });

    it('honours the Retry-After of a 503 before retrying', async () => {
      await mountWith(authenticatedBootstrap);
      vi.mocked(Math.random).mockReturnValue(0);
      axiosMock.onGet(ENDPOINT).reply(503, { error: 'Snapshot ordering unavailable' }, { 'retry-after': '5' });

      await store.refresh({ kind: 'ordinary', reason: 'interval' });
      expect(requests()).toBe(1);

      await vi.advanceTimersByTimeAsync(4999);
      expect(requests()).toBe(1);
      await vi.advanceTimersByTimeAsync(1);
      expect(requests()).toBe(2);
    });

    it('never retries in a tight loop while the server stays down', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(500);

      await store.refresh({ kind: 'ordinary', reason: 'interval' });
      await vi.advanceTimersByTimeAsync(10 * 60 * 1000);

      // Draw 0.5: 1s, 2s, 4s, 8s, 16s, then 30s each. About 24 in ten minutes.
      expect(requests()).toBeGreaterThan(5);
      expect(requests()).toBeLessThan(30);
    });

    it('even the worst draw cannot beat the floor', async () => {
      await mountWith(authenticatedBootstrap);
      vi.mocked(Math.random).mockReturnValue(0);
      axiosMock.onGet(ENDPOINT).reply(500);

      await store.refresh({ kind: 'ordinary', reason: 'interval' });
      await vi.advanceTimersByTimeAsync(10 * 1000);

      expect(requests()).toBeLessThanOrEqual(11);
    });

    it('a success cancels the pending retry', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).replyOnce(500).onGet(ENDPOINT).reply(() => [200, next(authenticatedBootstrap)]);

      await store.refresh({ kind: 'ordinary', reason: 'interval' });
      await store.retryNow();
      const settled = requests();
      await vi.advanceTimersByTimeAsync(60 * 1000);

      expect(requests()).toBe(settled);
    });
  });

  describe('triggers', () => {
    const setVisibility = (state: DocumentVisibilityState) => {
      vi.spyOn(document, 'visibilityState', 'get').mockReturnValue(state);
      document.dispatchEvent(new Event('visibilitychange'));
    };

    it('returning to a STALE visible tab makes exactly one request', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(() => [200, next(authenticatedBootstrap)]);
      vi.setSystemTime(Date.now() + AUTH_CHECK_CONFIG.INTERVAL + 1000);

      setVisibility('visible');
      setVisibility('visible');
      await vi.advanceTimersByTimeAsync(0);

      expect(requests()).toBe(1);
    });

    it('returning to a FRESH tab makes none', async () => {
      await mountWith(authenticatedBootstrap);
      setVisibility('visible');
      await vi.advanceTimersByTimeAsync(0);

      expect(requests()).toBe(0);
    });

    it('hiding a tab makes none', async () => {
      await mountWith(authenticatedBootstrap);
      vi.setSystemTime(Date.now() + AUTH_CHECK_CONFIG.INTERVAL + 1000);
      setVisibility('hidden');
      await vi.advanceTimersByTimeAsync(0);

      expect(requests()).toBe(0);
    });

    it('an anonymous tab never polls', async () => {
      await mountWith(anonymousBootstrap);
      vi.setSystemTime(Date.now() + AUTH_CHECK_CONFIG.INTERVAL + 1000);
      setVisibility('visible');
      await vi.advanceTimersByTimeAsync(AUTH_CHECK_CONFIG.INTERVAL * 3);

      expect(requests()).toBe(0);
    });

    it('the passive interval fires once per interval while authenticated', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(() => [200, next(authenticatedBootstrap)]);

      await vi.advanceTimersByTimeAsync(AUTH_CHECK_CONFIG.INTERVAL + AUTH_CHECK_CONFIG.JITTER);
      expect(requests()).toBe(1);
      await vi.advanceTimersByTimeAsync(AUTH_CHECK_CONFIG.INTERVAL + AUTH_CHECK_CONFIG.JITTER);
      expect(requests()).toBe(2);
    });

    it('stop() ends the interval and invalidates what is in flight', async () => {
      await mountWith(authenticatedBootstrap);
      const late = deferred();
      axiosMock.onGet(ENDPOINT).replyOnce(() => late.promise);

      const pending = store.refresh({ kind: 'ordinary', reason: 'interval' });
      store.stop();
      late.resolve([200, toWire(anonymousBootstrap)]);

      expect(await pending).toBe('superseded');
      expect(store.authStatus).toBe('authenticated');
      await vi.advanceTimersByTimeAsync(AUTH_CHECK_CONFIG.INTERVAL * 2);
      expect(requests()).toBe(1);
    });
  });

  describe('/signin never redirects to Dashboard from a status that is not authenticated', () => {
    it.each([
      ['checking', null],
      ['anonymous', anonymousBootstrap],
      ['mfa_pending', mfaPendingBootstrap],
      ['unavailable', unavailableBootstrap],
    ] as const)('%s is not fully authenticated', async (status, hydration) => {
      await mountWith(hydration);

      expect(store.authStatus).toBe(status);
      expect(store.isFullyAuthenticated).toBe(false);
      expect(store.isAuthenticated).toBe(false);
    });

    it('cached authentication stops counting once verification keeps failing', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(500);
      for (let i = 0; i < AUTH_CHECK_CONFIG.MAX_FAILURES; i++) await store.retryNow();

      expect(store.isFullyAuthenticated).toBe(false);
    });

    it('a rejection is not reversed by hydration-era state, storage, or a late response', async () => {
      await mountWith(authenticatedBootstrap);
      sessionStorage.setItem('ots_auth_state', 'true');
      const late = deferred();
      axiosMock.onGet(ENDPOINT).replyOnce(() => late.promise).onGet(ENDPOINT).reply(200, toWire(anonymousBootstrap));

      const stale = store.refresh({ kind: 'ordinary', reason: 'interval' });
      await store.refresh({ kind: 'auth-mutation', reason: 'login' });
      late.resolve([200, next(authenticatedBootstrap)]);
      await stale;

      expect(store.authStatus).toBe('anonymous');
      expect(store.isFullyAuthenticated).toBe(false);
    });
  });
});
