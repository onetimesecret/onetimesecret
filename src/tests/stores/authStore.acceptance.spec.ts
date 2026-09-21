// src/tests/stores/authStore.acceptance.spec.ts
//
// #4464: the coordinator accepts complete snapshots by epoch, version and
// request generation (ADR-046 "Client acceptance", "Downgrade guard").
// The rules themselves are tabled in src/tests/utils/snapshotOrdering.spec.ts;
// this file proves what the coordinator DOES with each decision.

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { _resetForTesting, getBootstrapSnapshot } from '@/services/bootstrap.service';
import * as diagnostics from '@/services/diagnostics.service';
import { AUTH_CHECK_CONFIG, useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import {
  anonymousBootstrap,
  authenticatedBootstrap,
  inOtherEpoch,
  mfaPendingBootstrap,
  mockCustomer,
  newerSnapshot,
  otherSnapshotEpoch,
  snapshotOrdering,
} from '@/tests/fixtures/bootstrap.fixture';
import { toWire } from '@/tests/fixtures/bootstrap-wire';
import { attemptForcedPageLoad } from '@/utils/forcedPageLoad';
import { consumeSessionTransition, SESSION_TRANSITION_KEY } from '@/utils/sessionTransition';
import { addBreadcrumb } from '@sentry/vue';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';

vi.mock('@/utils/forcedPageLoad', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/utils/forcedPageLoad')>()),
  attemptForcedPageLoad: vi.fn(() => 'reloading'),
}));

vi.mock('@sentry/vue', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@sentry/vue')>()),
  addBreadcrumb: vi.fn(),
}));

const ENDPOINT = AUTH_CHECK_CONFIG.ENDPOINT;
const BOOTSTRAP_KEY = '__BOOTSTRAP_ME__';
const EPOCH = snapshotOrdering.snapshot_epoch;
const VERSION = snapshotOrdering.snapshot_version;

/** Hydration as a pre-contract (or degraded) server renders it: no pair. */
function unordered(payload: BootstrapPayload): BootstrapPayload {
  const { snapshot_epoch: _e, snapshot_version: _v, snapshot_generated_at: _g, ...rest } = payload;
  return rest as BootstrapPayload;
}

describe('authStore snapshot acceptance (#4464)', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useAuthStore>;
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  async function mountWith(
    hydration: BootstrapPayload | Record<string, unknown> | null,
    // Replies needed by a request that init() itself makes.
    arrange?: (mock: AxiosMockAdapter) => void
  ) {
    _resetForTesting();
    const win = window as unknown as Record<string, unknown>;
    if (hydration) win[BOOTSTRAP_KEY] = toWire(hydration as BootstrapPayload);
    else delete win[BOOTSTRAP_KEY];

    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock as AxiosMockAdapter;
    bootstrapStore = useBootstrapStore();
    store = useAuthStore();
    arrange?.(axiosMock);
    vi.useFakeTimers();
    bootstrapStore.init();
    store.init();
  }

  const requests = () => axiosMock.history.get.filter((r) => r.url === ENDPOINT).length;
  const events = () =>
    vi
      .mocked(addBreadcrumb)
      .mock.calls.map(([crumb]) => crumb)
      .filter((crumb) => crumb.category === 'bootstrap.ordering');
  const eventNames = () => events().map((crumb) => crumb.message);

  /** Everything a refused snapshot must leave alone. */
  function observe() {
    return {
      store: structuredClone(JSON.parse(JSON.stringify(bootstrapStore.$state))),
      mirror: structuredClone(JSON.parse(JSON.stringify(getBootstrapSnapshot()))),
      status: store.authStatus,
    };
  }

  beforeEach(() => {
    vi.spyOn(Math, 'random').mockReturnValue(0.5);
    vi.mocked(attemptForcedPageLoad).mockClear();
    vi.mocked(addBreadcrumb).mockClear();
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

  describe('hydration', () => {
    it('establishes the initial watermark from its validated pair, with no request', async () => {
      await mountWith(authenticatedBootstrap);

      expect(bootstrapStore.watermark).toEqual({ epoch: EPOCH, version: VERSION });
      expect(requests()).toBe(0);
    });

    it('an anonymous tab is unordered and does not refresh', async () => {
      await mountWith(anonymousBootstrap);

      expect(bootstrapStore.watermark).toBeNull();
      expect(requests()).toBe(0);
    });

    it('degraded hydration (a session, no pair) schedules exactly one immediate ordinary refresh', async () => {
      await mountWith(unordered(authenticatedBootstrap));

      expect(store.authStatus).toBe('authenticated');
      expect(bootstrapStore.watermark).toBeNull();
      expect(requests()).toBe(1);
      expect(eventNames()).toContain('degraded-hydration');
    });

    it('a malformed hydration pair starts the tab unordered instead of discarding the page state', async () => {
      await mountWith({ ...authenticatedBootstrap, snapshot_version: '1.7e15' });

      expect(store.authStatus).toBe('authenticated');
      expect(bootstrapStore.watermark).toBeNull();
      expect(requests()).toBe(1);
    });

    it('an unordered tab applies snapshots until the first ordered one establishes the watermark', async () => {
      await mountWith(unordered(authenticatedBootstrap), (mock) =>
        mock
          .onGet(ENDPOINT)
          .replyOnce(200, toWire(unordered(authenticatedBootstrap)))
          .onGet(ENDPOINT)
          .replyOnce(200, toWire(authenticatedBootstrap))
      );
      await vi.advanceTimersByTimeAsync(0);
      expect(requests()).toBe(1);
      expect(bootstrapStore.watermark).toBeNull();

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('applied');

      expect(bootstrapStore.watermark).toEqual({ epoch: EPOCH, version: VERSION });
    });
  });

  describe('strictly newer', () => {
    it('applies and advances the watermark', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(newerSnapshot(authenticatedBootstrap, 7)));

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('applied');

      expect(bootstrapStore.watermark?.version).toBe((BigInt(VERSION) + 7n).toString());
    });

    it('a local patch never advances or replaces the watermark', async () => {
      await mountWith(authenticatedBootstrap);

      bootstrapStore.update({
        snapshot_epoch: otherSnapshotEpoch,
        snapshot_version: '99999999999999999999',
        email: 'patched@example.com',
      });

      expect(bootstrapStore.email).toBe('patched@example.com');
      expect(bootstrapStore.watermark).toEqual({ epoch: EPOCH, version: VERSION });
    });

    it('a malformed snapshot_generated_at still applies, with a diagnostic and an unknown age', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, {
        ...(toWire(newerSnapshot(authenticatedBootstrap)) as object),
        snapshot_generated_at: '2026-09-17T17:28:59.123Z',
      });

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('applied');

      const crumb = events().find((c) => c.message === 'generated-at-malformed');
      expect(crumb?.data).toMatchObject({ age: 'unknown', epoch: EPOCH });
    });

    it('a missing snapshot_generated_at applies too', async () => {
      await mountWith(authenticatedBootstrap);
      const wire = toWire(newerSnapshot(authenticatedBootstrap)) as Record<string, unknown>;
      delete wire.snapshot_generated_at;
      axiosMock.onGet(ENDPOINT).reply(200, wire);

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('applied');
      expect(eventNames()).toContain('generated-at-missing');
    });

    it('a clock regression is a diagnostic and never a rejection', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, {
        ...(toWire(newerSnapshot(authenticatedBootstrap)) as object),
        snapshot_generated_at: '2026-09-17T17:00:00.000000Z',
      });

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('applied');
      expect(eventNames()).toContain('clock-regression');
    });

    it('a generation time far in the future changes nothing either', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, {
        ...(toWire(authenticatedBootstrap) as object),
        snapshot_generated_at: '2099-01-01T00:00:00.000000Z',
      });

      // Same version as the watermark: newer by the clock, an anomaly by order.
      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('refused');
    });
  });

  describe('anomalies: one immediate retry, then a forced page load', () => {
    const causes: Array<[string, (p: BootstrapPayload) => unknown]> = [
      ['an equal version (replayed response)', (p) => toWire(p)],
      ['a lower version (clock regression across a key loss)', (p) => toWire({ ...p, snapshot_version: '5' })],
      ['a missing pair (worker that predates the contract)', (p) => toWire(unordered(p))],
      ['a malformed pair', (p) => ({ ...(toWire(p) as object), snapshot_version: 17 })],
    ];

    it.each(causes)('%s: refused, retried once, recovers when the retry is good', async (_n, bad) => {
      await mountWith(authenticatedBootstrap);
      axiosMock
        .onGet(ENDPOINT)
        .replyOnce(200, bad(authenticatedBootstrap))
        .onGet(ENDPOINT)
        .replyOnce(200, toWire(newerSnapshot(authenticatedBootstrap)));

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('applied');

      expect(requests()).toBe(2);
      expect(attemptForcedPageLoad).not.toHaveBeenCalled();
      expect(store.staleSession).toBe(false);
      expect(eventNames()).toContain('anomaly');
    });

    it.each(causes)('%s twice: forced page load, nothing mutated', async (_n, bad) => {
      await mountWith(authenticatedBootstrap);
      const before = observe();
      const setActor = vi.spyOn(diagnostics, 'setDiagnosticsActorContext');
      const reset = vi.spyOn(useOrganizationStore(), '$reset');
      axiosMock.onGet(ENDPOINT).reply(200, bad(authenticatedBootstrap));

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('refused');

      expect(requests()).toBe(2);
      expect(attemptForcedPageLoad).toHaveBeenCalledTimes(1);
      expect(store.staleSession).toBe(true);
      expect(observe()).toEqual(before);
      expect(setActor).not.toHaveBeenCalled();
      expect(reset).not.toHaveBeenCalled();
      // An anomaly is not a session transition: no message is parked.
      expect(sessionStorage.getItem(SESSION_TRANSITION_KEY)).toBeNull();
    });

    it('a retired epoch is refused even though this tab is unordered', async () => {
      await mountWith(authenticatedBootstrap);
      await store.logout();
      expect(bootstrapStore.retiredEpochs).toEqual([EPOCH]);
      expect(bootstrapStore.watermark).toBeNull();
      axiosMock.onGet(ENDPOINT).reply(200, toWire(newerSnapshot(authenticatedBootstrap)));

      expect(await store.refresh({ kind: 'auth-mutation', reason: 'login' })).toBe('refused');

      expect(store.authStatus).toBe('anonymous');
      expect(bootstrapStore.cust).toBeNull();
    });

    it('anomalies are consecutive across refreshes; an applied snapshot resets the count', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock
        .onGet(ENDPOINT)
        .replyOnce(200, toWire(authenticatedBootstrap))
        .onGet(ENDPOINT)
        .replyOnce(200, toWire(newerSnapshot(authenticatedBootstrap, 1)))
        .onGet(ENDPOINT)
        .replyOnce(200, toWire(newerSnapshot(authenticatedBootstrap, 1)))
        .onGet(ENDPOINT)
        .replyOnce(200, toWire(newerSnapshot(authenticatedBootstrap, 2)));

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('applied');
      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('applied');

      expect(requests()).toBe(4);
      expect(attemptForcedPageLoad).not.toHaveBeenCalled();
    });

    it('the retry takes the next generation, and joiners wait for its answer', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock
        .onGet(ENDPOINT)
        .replyOnce(200, toWire(authenticatedBootstrap))
        .onGet(ENDPOINT)
        .replyOnce(200, toWire(newerSnapshot(authenticatedBootstrap)));

      const outcomes = await Promise.all([
        store.refresh({ kind: 'ordinary', reason: 'interval' }),
        store.refresh({ kind: 'ordinary', reason: 'visibility' }),
      ]);

      expect(outcomes).toEqual(['applied', 'applied']);
      expect(requests()).toBe(2);
    });
  });

  describe('the end of a session always reaches the tab', () => {
    const endings: Array<[string, unknown]> = [
      ['session expiry or revocation (no ordering metadata)', toWire(anonymousBootstrap)],
      [
        'logout in another tab (a renewed SID, stray metadata)',
        { ...(toWire(anonymousBootstrap) as object), ...inOtherEpoch(authenticatedBootstrap), authenticated: false, auth_status: 'anonymous', cust: null, custid: '', email: '' },
      ],
      [
        'an ended session carrying a LOWER version',
        { ...(toWire(anonymousBootstrap) as object), snapshot_epoch: EPOCH, snapshot_version: '1' },
      ],
      [
        'an ended session carrying a malformed pair',
        { ...(toWire(anonymousBootstrap) as object), snapshot_epoch: 'nope' },
      ],
    ];

    it.each(endings)('%s: forced page load on an ordinary refresh, not applied in place', async (_n, body) => {
      await mountWith(authenticatedBootstrap);
      const before = observe();
      axiosMock.onGet(ENDPOINT).reply(200, body);

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('refused');

      expect(requests()).toBe(1);
      expect(attemptForcedPageLoad).toHaveBeenCalledTimes(1);
      expect(store.staleSession).toBe(true);
      expect(observe()).toEqual(before);
      expect(consumeSessionTransition()).toBe('ended');
      expect(eventNames()).toContain('session-ended');
    });

    it('reaches a tab whose verification had been failing (status unavailable)', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).networkError();
      for (let i = 0; i < AUTH_CHECK_CONFIG.MAX_FAILURES; i++) {
        await store.refresh({ kind: 'ordinary', reason: 'retry' });
      }
      expect(store.authStatus).toBe('unavailable');
      axiosMock.reset();
      axiosMock.onGet(ENDPOINT).reply(200, toWire(anonymousBootstrap));

      expect(await store.retryNow()).toBe('refused');
      expect(attemptForcedPageLoad).toHaveBeenCalledTimes(1);
    });

    it("this tab's own logout is applied atomically, retires the epoch and leaves the tab unordered", async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(anonymousBootstrap));

      expect(await store.refresh({ kind: 'auth-mutation', reason: 'check' })).toBe('applied');

      expect(store.authStatus).toBe('anonymous');
      expect(bootstrapStore.cust).toBeNull();
      expect(bootstrapStore.watermark).toBeNull();
      expect(bootstrapStore.retiredEpochs).toEqual([EPOCH]);
      expect(attemptForcedPageLoad).not.toHaveBeenCalled();
    });
  });

  describe('session replaced', () => {
    it('on an ordinary refresh: forced page load, the other account is never applied', async () => {
      await mountWith(authenticatedBootstrap);
      const before = observe();
      axiosMock.onGet(ENDPOINT).reply(
        200,
        toWire({
          ...inOtherEpoch(authenticatedBootstrap),
          cust: { ...mockCustomer, extid: 'ur-b', email: 'b@example.com' },
          custid: 'ur-b',
          email: 'b@example.com',
        })
      );

      expect(await store.refresh({ kind: 'ordinary', reason: 'visibility' })).toBe('refused');

      expect(observe()).toEqual(before);
      expect(bootstrapStore.custid).toBe(mockCustomer.extid);
      expect(attemptForcedPageLoad).toHaveBeenCalledTimes(1);
      expect(consumeSessionTransition()).toBe('replaced');
      expect(eventNames()).toContain('session-replaced');
    });

    it('on an authentication mutation: accepted as the start of a new stream', async () => {
      await mountWith(mfaPendingBootstrap);
      // Completing MFA may renew the SID; the new epoch may carry ANY version.
      axiosMock
        .onGet(ENDPOINT)
        .reply(200, toWire({ ...inOtherEpoch(authenticatedBootstrap), snapshot_version: '3' }));

      expect(await store.refresh({ kind: 'auth-mutation', reason: 'mfa' })).toBe('applied');

      expect(store.authStatus).toBe('authenticated');
      expect(bootstrapStore.watermark).toEqual({ epoch: otherSnapshotEpoch, version: '3' });
      expect(bootstrapStore.retiredEpochs).toEqual([EPOCH]);
    });

    it('only the current generation may establish a new epoch', async () => {
      await mountWith(authenticatedBootstrap);
      let release!: (reply: [number, unknown]) => void;
      const late = new Promise<[number, unknown]>((resolve) => (release = resolve));
      axiosMock
        .onGet(ENDPOINT)
        .replyOnce(() => late)
        .onGet(ENDPOINT)
        .replyOnce(200, toWire(newerSnapshot(authenticatedBootstrap)));

      const stale = store.refresh({ kind: 'auth-mutation', reason: 'login' });
      await store.refresh({ kind: 'auth-mutation', reason: 'login' });
      release([200, toWire(inOtherEpoch(authenticatedBootstrap))]);

      expect(await stale).toBe('superseded');
      expect(bootstrapStore.watermark?.epoch).toBe(EPOCH);
      expect(eventNames()).toContain('generation-invalidated');
    });
  });

  describe('the stale-session state', () => {
    it('stops ordinary refreshes and applies nothing afterwards', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).replyOnce(200, toWire(anonymousBootstrap));
      await store.refresh({ kind: 'ordinary', reason: 'interval' });
      const made = requests();
      axiosMock.onGet(ENDPOINT).reply(200, toWire(newerSnapshot(authenticatedBootstrap)));

      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('refused');
      expect(await store.refresh({ kind: 'auth-mutation', reason: 'login' })).toBe('refused');
      await vi.advanceTimersByTimeAsync(AUTH_CHECK_CONFIG.INTERVAL * 3);

      expect(requests()).toBe(made);
      expect(store.authCheckTimer).toBeNull();
      // The reload is attempted once and never retried.
      expect(attemptForcedPageLoad).toHaveBeenCalledTimes(1);
    });

    it('is entered BEFORE the reload is attempted', async () => {
      await mountWith(authenticatedBootstrap);
      let staleAtReload: boolean | null = null;
      vi.mocked(attemptForcedPageLoad).mockImplementationOnce(() => {
        staleAtReload = store.staleSession;
        return 'reloading';
      });

      store.forcePageLoad('ended');

      expect(staleAtReload).toBe(true);
    });
  });

  describe('failures', () => {
    it('a failed refresh retains the last accepted state and its watermark', async () => {
      await mountWith(authenticatedBootstrap);
      const before = observe();
      axiosMock.onGet(ENDPOINT).reply(503, { error_type: 'SnapshotOrderingUnavailable' }, { 'retry-after': '5' });

      // PR #4497 item 11: allocation 503 returns a distinct outcome and does
      // NOT increment failureCount / withhold authority.
      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe(
        'allocation-unavailable'
      );

      expect(observe()).toEqual(before);
      expect(eventNames()).toContain('allocation-failure');
      expect(attemptForcedPageLoad).not.toHaveBeenCalled();
    });

    it('diagnostics carry ordering metadata only, never payload contents', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(anonymousBootstrap));
      await store.refresh({ kind: 'ordinary', reason: 'interval' });

      const allowed = new Set([
        'event', 'generation', 'kind', 'epoch', 'version', 'prior_epoch', 'prior_version',
        'pair_malformed', 'cause', 'consecutive', 'age', 'result',
      ]);
      for (const crumb of events()) {
        for (const key of Object.keys(crumb.data ?? {})) expect(allowed.has(key)).toBe(true);
      }
      expect(JSON.stringify(events())).not.toContain(mockCustomer.email);
    });
  });
});
