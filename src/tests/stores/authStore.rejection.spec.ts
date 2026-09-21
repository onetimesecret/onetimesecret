// src/tests/stores/authStore.rejection.spec.ts
//
// #4460: session rejection and verification-unavailable are handled
// distinctly. A verification outage never logs the user out.

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { _resetForTesting, getBootstrapSnapshot } from '@/services/bootstrap.service';
import { AUTH_CHECK_CONFIG, useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import {
  anonymousBootstrap,
  authenticatedBootstrap,
  mfaPendingBootstrap,
  newerSnapshot,
  unavailableBootstrap,
} from '@/tests/fixtures/bootstrap.fixture';
import { toWire } from '@/tests/fixtures/bootstrap-wire';
import { attemptForcedPageLoad } from '@/utils/forcedPageLoad';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';

vi.mock('@/utils/forcedPageLoad', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/utils/forcedPageLoad')>()),
  attemptForcedPageLoad: vi.fn(() => 'reloading'),
}));

const ENDPOINT = AUTH_CHECK_CONFIG.ENDPOINT;
const BOOTSTRAP_KEY = '__BOOTSTRAP_ME__';

describe('authStore: rejection vs verification-unavailable (#4460)', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useAuthStore>;
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  async function mountWith(hydration: BootstrapPayload) {
    _resetForTesting();
    (window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY] = toWire(hydration);
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock as AxiosMockAdapter;
    bootstrapStore = useBootstrapStore();
    store = useAuthStore();
    vi.useFakeTimers();
    bootstrapStore.init();
    store.init();
  }

  const requests = () => axiosMock.history.get.filter((r) => r.url === ENDPOINT).length;
  const held = () => ({
    store: JSON.parse(JSON.stringify({ ...bootstrapStore.$state, authStatus: null })),
    mirror: JSON.parse(JSON.stringify(getBootstrapSnapshot())),
  });

  beforeEach(() => {
    vi.spyOn(Math, 'random').mockReturnValue(0.5);
    vi.mocked(attemptForcedPageLoad).mockClear();
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

  describe('no number of failures logs the user out', () => {
    // NB: SnapshotOrderingUnavailable (allocation 503) is covered separately
    // below (PR #4497 item 11). It must NOT cascade into withhold-authority
    // for signed-in users, so it does NOT participate in this shared loop.
    const outages: Array<[string, (mock: AxiosMockAdapter) => void]> = [
      ['transport failures', (mock) => mock.onGet(ENDPOINT).networkError()],
      ['timeouts', (mock) => mock.onGet(ENDPOINT).timeout()],
      ['500s', (mock) => mock.onGet(ENDPOINT).reply(500)],
      [
        'server snapshots that say `unavailable`',
        (mock) => mock.onGet(ENDPOINT).reply(200, toWire(unavailableBootstrap)),
      ],
    ];

    it.each(outages)('100 consecutive %s', async (_name, arrange) => {
      await mountWith(authenticatedBootstrap);
      const logout = vi.spyOn(store, 'logout');
      const before = held();
      arrange(axiosMock);

      for (let i = 1; i <= 100; i++) {
        expect(await store.refresh({ kind: 'ordinary', reason: 'retry' })).toBe('failed');
        expect(store.authStatus).toBe(
          i < AUTH_CHECK_CONFIG.MAX_FAILURES ? 'authenticated' : 'unavailable'
        );
      }

      // The last accepted snapshot is untouched, in the store and the mirror.
      expect(held()).toEqual(before);
      expect(bootstrapStore.cust).not.toBeNull();
      expect(logout).not.toHaveBeenCalled();
      expect(attemptForcedPageLoad).not.toHaveBeenCalled();
      expect(store.staleSession).toBe(false);
      // Client-side storage was not cleared as a logout would.
      expect(store.isAuthenticated).toBe(false);
    });

    it('keeps retrying at a capped interval while unavailable', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).networkError();
      await store.refresh({ kind: 'ordinary', reason: 'interval' });

      // Let the backoff climb to its cap, then measure a steady-state window.
      await vi.advanceTimersByTimeAsync(5 * AUTH_CHECK_CONFIG.BACKOFF_CAP);
      expect(store.authStatus).toBe('unavailable');
      const atCap = requests();

      await vi.advanceTimersByTimeAsync(10 * AUTH_CHECK_CONFIG.BACKOFF_CAP);

      // Full jitter with the draw pinned at 0.5: one retry per half cap.
      // Retries continue, and never faster than that.
      const made = requests() - atCap;
      expect(made).toBeGreaterThanOrEqual(19);
      expect(made).toBeLessThanOrEqual(21);
    });

    it('the first successful refresh applies whatever the server reports: still signed in', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).networkError();
      for (let i = 0; i < 5; i++) await store.refresh({ kind: 'ordinary', reason: 'retry' });
      expect(store.authStatus).toBe('unavailable');
      axiosMock.reset();
      axiosMock.onGet(ENDPOINT).reply(200, toWire(newerSnapshot(authenticatedBootstrap)));

      expect(await store.retryNow()).toBe('applied');

      expect(store.authStatus).toBe('authenticated');
      expect(store.failureCount).toBe(0);
      expect(attemptForcedPageLoad).not.toHaveBeenCalled();
    });
  });

  describe('SnapshotOrderingUnavailable 503 does not cascade to withhold (PR #4497 item 11)', () => {
    it('returns allocation-unavailable, does not increment failureCount, does not withhold', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock
        .onGet(ENDPOINT)
        .reply(503, { error_type: 'SnapshotOrderingUnavailable' }, { 'retry-after': '5' });

      for (let i = 1; i <= 100; i++) {
        expect(await store.refresh({ kind: 'ordinary', reason: 'retry' })).toBe(
          'allocation-unavailable'
        );
        // Never crosses MAX_FAILURES — the last accepted snapshot stands and
        // failureCount is not incremented (stays at its hydration-era value,
        // which is `null` when nothing has committed here).
        expect(store.authStatus).toBe('authenticated');
        expect(store.failureCount ?? 0).toBe(0);
      }
      expect(bootstrapStore.cust).not.toBeNull();
      expect(attemptForcedPageLoad).not.toHaveBeenCalled();
      expect(store.staleSession).toBe(false);
    });

    it('schedules a bounded retry driven by Retry-After', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock
        .onGet(ENDPOINT)
        .reply(503, { error_type: 'SnapshotOrderingUnavailable' }, { 'retry-after': '5' });

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe(
        'allocation-unavailable'
      );
      expect(requests()).toBe(1);

      // Before the Retry-After elapses no new request has fired.
      await vi.advanceTimersByTimeAsync(4_000);
      expect(requests()).toBe(1);

      // At the Retry-After the coordinator retries once.
      await vi.advanceTimersByTimeAsync(2_000);
      expect(requests()).toBe(2);
    });

    it('a checking tab is not withheld by a single allocation 503 (would have been with noteFailure)', async () => {
      // A `checking` tab (no hydration) is the worst case for withhold-cascade:
      // noteFailure() would immediately transition it to `unavailable`. The
      // allocation path must NOT touch failureCount, so the status stays
      // `checking` and the tab keeps retrying without blanking the UI.
      await mountWith({} as BootstrapPayload);
      axiosMock
        .onGet(ENDPOINT)
        .reply(503, { error_type: 'SnapshotOrderingUnavailable' }, { 'retry-after': '5' });

      const prior = store.authStatus;
      const priorCount = store.failureCount;
      expect(await store.refresh({ kind: 'ordinary', reason: 'retry' })).toBe(
        'allocation-unavailable'
      );
      // Not incremented — failureCount is unchanged (still whatever hydration
      // set, typically null for a checking tab).
      expect(store.failureCount).toBe(priorCount);
      expect(store.authStatus).toBe(prior);
    });
  });

  describe('a definitive rejection', () => {
    it('cannot be reversed by hydration-era state, session storage, or a late response', async () => {
      await mountWith(authenticatedBootstrap);
      sessionStorage.setItem('ots_auth_state', 'true');
      let release!: (reply: [number, unknown]) => void;
      const late = new Promise<[number, unknown]>((resolve) => (release = resolve));
      axiosMock
        .onGet(ENDPOINT)
        .replyOnce(() => late)
        .onGet(ENDPOINT)
        .replyOnce(200, toWire(anonymousBootstrap));

      const stale = store.refresh({ kind: 'ordinary', reason: 'interval' });
      // This tab signs out: the server's statement is applied atomically.
      expect(await store.refresh({ kind: 'auth-mutation', reason: 'check' })).toBe('applied');
      release([200, toWire(newerSnapshot(authenticatedBootstrap, 50))]);

      expect(await stale).toBe('superseded');
      expect(store.authStatus).toBe('anonymous');
      expect(bootstrapStore.cust).toBeNull();
      expect(getBootstrapSnapshot()?.cust ?? null).toBeNull();

      // Not even a well-formed, newer snapshot of the ended session revives it.
      axiosMock.onGet(ENDPOINT).reply(200, toWire(newerSnapshot(authenticatedBootstrap, 99)));
      expect(await store.refresh({ kind: 'ordinary', reason: 'csrf' })).toBe('refused');
      expect(bootstrapStore.cust).toBeNull();
    });
  });

  describe('noteApiRejection requests reconciliation and writes nothing', () => {
    const revoked = { code: 'active_session_revoked', code_scope: 'customer_session' } as const;

    it('a customer_session rejection makes exactly one request, however many calls failed', async () => {
      await mountWith(authenticatedBootstrap);
      const before = held();
      axiosMock.onGet(ENDPOINT).reply(200, toWire(newerSnapshot(authenticatedBootstrap)));

      for (let i = 0; i < 5; i++) store.noteApiRejection(revoked);

      expect(requests()).toBe(1);
      // Nothing was written by the handler itself.
      expect(store.authStatus).toBe('authenticated');
      expect(held()).toEqual(before);
    });

    it('the reconciliation, not the handler, ends the session: forced page load', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(anonymousBootstrap));

      store.noteApiRejection(revoked);
      await vi.advanceTimersByTimeAsync(0);

      expect(attemptForcedPageLoad).toHaveBeenCalledTimes(1);
      expect(store.staleSession).toBe(true);
    });

    it('a storm of rejections cannot become a storm of requests', async () => {
      await mountWith(authenticatedBootstrap);
      let n = 0;
      axiosMock.onGet(ENDPOINT).reply(() => [200, toWire(newerSnapshot(authenticatedBootstrap, ++n))]);

      for (let i = 0; i < 20; i++) {
        store.noteApiRejection(revoked);
        await vi.advanceTimersByTimeAsync(100);
      }

      expect(requests()).toBe(1);
      await vi.advanceTimersByTimeAsync(AUTH_CHECK_CONFIG.REJECTION_MIN_INTERVAL);
      store.noteApiRejection(revoked);
      expect(requests()).toBe(2);
    });

    it('an admin-only timeout leaves the customer session intact: no request, no change', async () => {
      await mountWith(authenticatedBootstrap);
      const before = held();

      store.noteApiRejection({ code: 'admin_session_expired', code_scope: 'admin_session' });
      await vi.advanceTimersByTimeAsync(0);

      expect(requests()).toBe(0);
      expect(store.authStatus).toBe('authenticated');
      expect(held()).toEqual(before);
    });

    it('a verification outage seen by many API calls counts as ONE failed verification', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(unavailableBootstrap));

      for (let i = 0; i < 10; i++) {
        store.noteApiRejection({
          code: 'active_session_unavailable',
          code_scope: 'verification_unavailable',
        });
      }
      await vi.advanceTimersByTimeAsync(0);

      expect(requests()).toBe(1);
      expect(store.failureCount).toBe(1);
      expect(store.authStatus).toBe('authenticated');
    });

    it('an uncoded 401 can only withhold: one reconciliation while a session is held', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(newerSnapshot(authenticatedBootstrap)));

      store.noteApiRejection(null);
      await vi.advanceTimersByTimeAsync(0);

      expect(requests()).toBe(1);
      expect(store.authStatus).toBe('authenticated');
    });

    it('a failed login on an anonymous tab (uncoded 401) reconciles nothing', async () => {
      await mountWith(anonymousBootstrap);

      store.noteApiRejection(null);
      store.noteApiRejection({ code: 'session_missing', code_scope: 'customer_session' });

      expect(requests()).toBe(0);
    });

    it('`awaiting_mfa` tells an MFA-pending tab nothing new', async () => {
      await mountWith(mfaPendingBootstrap);

      store.noteApiRejection({ code: 'awaiting_mfa', code_scope: 'customer_session' });

      expect(requests()).toBe(0);
    });
  });
});
