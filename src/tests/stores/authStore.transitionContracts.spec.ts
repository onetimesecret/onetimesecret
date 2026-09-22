// src/tests/stores/authStore.transitionContracts.spec.ts
//
// PR #4497 caller contracts (ADR-046#caller-contracts):
//   init() recovery for `unavailable` hydration (ADR-046#authority-action-gating)
//   generation ownership across commit() cleanup (ADR-046#commit-generation-ownership)
//   rejection disposition surfaces user-visible feedback (ADR-046#rejection-disposition)
//
// The tests here target each arc's regression scenario. Style follows the
// existing coordinator / rejection specs alongside.

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { _resetForTesting } from '@/services/bootstrap.service';
import {
  AUTH_CHECK_CONFIG,
  COORDINATOR_DISPOSITION_KEY,
  readCoordinatorDisposition,
  useAuthStore,
} from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import {
  anonymousBootstrap,
  authenticatedBootstrap,
  mfaPendingBootstrap,
  mockCustomer,
  newerSnapshot,
  inOtherEpoch,
  unavailableBootstrap,
} from '@/tests/fixtures/bootstrap.fixture';
import { toWire } from '@/tests/fixtures/bootstrap-wire';
import { attemptForcedPageLoad } from '@/utils/forcedPageLoad';
import { addBreadcrumb } from '@sentry/vue';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { getActivePinia } from 'pinia';
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

// receiptListStore is outside this spec's static import graph, so the first
// dynamic import of it (from clearAccountScopedState) waits on this gate. That
// lets a test hold an older commit inside its cleanup while a newer one lands.
const receiptListImport = vi.hoisted(() => {
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  return { gate, release, reset: vi.fn() };
});

vi.mock('@/shared/stores/receiptListStore', async () => {
  await receiptListImport.gate;
  return { useReceiptListStore: () => ({ $reset: receiptListImport.reset }) };
});

// A second one-shot gate: a module import resolves once per file, so a later
// case that needs a parked commit must gate a store no earlier case imported.
const receiptImport = vi.hoisted(() => {
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  return { gate, release };
});

vi.mock('@/shared/stores/receiptStore', async () => {
  await receiptImport.gate;
  return { useReceiptStore: () => ({ $reset: vi.fn() }) };
});

const ENDPOINT = AUTH_CHECK_CONFIG.ENDPOINT;
const BOOTSTRAP_KEY = '__BOOTSTRAP_ME__';

function deferred<T>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => (resolve = r));
  return { promise, resolve };
}

// Another account is another session: its snapshots start a new epoch.
const accountB: BootstrapPayload = {
  ...inOtherEpoch(authenticatedBootstrap),
  cust: { ...mockCustomer, objid: 'cust-b', extid: 'ur-b', email: 'b@example.com' },
  custid: 'ur-b',
  email: 'b@example.com',
};

describe('authStore PR #4497 transition contracts', () => {
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
    vi.useFakeTimers();
    bootstrapStore.init();
    store.init();
  }

  const requests = () => axiosMock.history.get.filter((r) => r.url === ENDPOINT).length;
  const orderingEvents = () =>
    vi
      .mocked(addBreadcrumb)
      .mock.calls.flatMap(([c]) => (c.category === 'bootstrap.ordering' ? [c.message] : []));

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

  // -------------------------------------------------------------------------
  // init() recovery for `unavailable` hydration (ADR-046#authority-action-gating)
  // -------------------------------------------------------------------------
  describe('unavailable hydration schedules bounded retry (ADR-046#authority-action-gating)', () => {
    it('a tab hydrated as `unavailable` retries within the backoff window without waiting 15 minutes', async () => {
      await mountWith(unavailableBootstrap);
      expect(store.authStatus).toBe('unavailable');
      // Nothing has failed yet inside this session; recovery is driven by init.
      expect(store.failureCount).toBeNull();
      expect(requests()).toBe(0);

      axiosMock.onGet(ENDPOINT).reply(200, toWire(newerSnapshot(authenticatedBootstrap)));

      // The recovery timer must be at most the cap: nowhere near the 15min interval.
      await vi.advanceTimersByTimeAsync(AUTH_CHECK_CONFIG.BACKOFF_CAP);

      expect(requests()).toBeGreaterThanOrEqual(1);
      expect(store.authStatus).toBe('authenticated');
    });

    it('the retry uses kind: ordinary (a verification, not an auth mutation)', async () => {
      await mountWith(unavailableBootstrap);
      axiosMock.onGet(ENDPOINT).networkError();

      await vi.advanceTimersByTimeAsync(AUTH_CHECK_CONFIG.BACKOFF_CAP);

      // Every recorded request went to the ordinary bootstrap/me endpoint; if
      // the code path had used an auth-mutation, it would have aborted any
      // in-flight refresh and started a fresh generation each time. Instead
      // the retry-after backoff advances one generation at a time.
      expect(requests()).toBeGreaterThanOrEqual(1);
      // And the store never claimed authentication despite the outage.
      expect(store.authStatus).toBe('unavailable');
      // failureCount advanced past the initial null: the timer fired.
      expect(store.failureCount).not.toBeNull();
    });

    it('a healthy hydration schedules no recovery', async () => {
      await mountWith(authenticatedBootstrap);
      expect(requests()).toBe(0);

      await vi.advanceTimersByTimeAsync(AUTH_CHECK_CONFIG.BACKOFF_CAP);

      // The passive 15min interval is out of range — nothing else should fire.
      expect(requests()).toBe(0);
    });
  });

  // -------------------------------------------------------------------------
  // generation ownership across commit() cleanup (ADR-046#commit-generation-ownership)
  // -------------------------------------------------------------------------
  describe('commit() gates post-await work on the generation (ADR-046#commit-generation-ownership)', () => {
    it("an older commit's post-await steps no-op when a newer refresh has taken the generation", async () => {
      await mountWith(authenticatedBootstrap);

      // Two auth-mutations in flight: the older resolves LAST but must not
      // clobber the newer generation's failureCount / lastCheckTime /
      // scheduled interval.
      const older = deferred<[number, unknown]>();
      const newer = deferred<[number, unknown]>();
      axiosMock
        .onGet(ENDPOINT)
        .replyOnce(() => older.promise)
        .onGet(ENDPOINT)
        .replyOnce(() => newer.promise);

      const first = store.refresh({ kind: 'auth-mutation', reason: 'login' });
      const second = store.refresh({ kind: 'auth-mutation', reason: 'account-switch' });

      // Newer resolves first: applies accountB.
      newer.resolve([200, toWire(accountB)]);
      expect(await second).toBe('applied');
      expect(bootstrapStore.custid).toBe('ur-b');
      const lastCheckAfterNewer = store.lastCheckTime;

      // Older resolves late with an authenticatedBootstrap snapshot for the
      // ORIGINAL account. Under the old code its commit() would await
      // clearAccountScopedState and then reset failureCount / lastCheckTime,
      // clobbering whatever the newer commit had set.
      older.resolve([200, toWire(newerSnapshot(authenticatedBootstrap))]);
      expect(await first).toBe('superseded');

      // The newer generation's state is intact.
      expect(bootstrapStore.custid).toBe('ur-b');
      expect(store.lastCheckTime).toBe(lastCheckAfterNewer);
    });

    it("an older commit held in its cleanup imports does not reset the stores a newer commit populated", async () => {
      await mountWith(authenticatedBootstrap);
      // Make receiptList an existing store so the cleanup must import it.
      const pinia = getActivePinia();
      if (!pinia) throw new Error('no active pinia');
      pinia.state.value.receiptList = {};

      // Older: an auth mutation ended the session. Losing authority sends
      // commit() into clearAccountScopedState, which parks on the gated import.
      axiosMock.onGet(ENDPOINT).replyOnce(200, toWire(newerSnapshot(anonymousBootstrap)));
      const first = store.refresh({ kind: 'auth-mutation', reason: 'password-change' });
      await vi.advanceTimersByTimeAsync(0);
      expect(bootstrapStore.custid).toBe(authenticatedBootstrap.custid);

      // Newer: same account, still authenticated. Nothing to clear, so it
      // applies straight away and takes the generation.
      axiosMock.onGet(ENDPOINT).replyOnce(200, toWire(newerSnapshot(authenticatedBootstrap)));
      expect(await store.refresh({ kind: 'auth-mutation', reason: 'login' })).toBe('applied');

      receiptListImport.release();
      // Its snapshot never landed, so it must not report 'applied'.
      expect(await first).toBe('superseded');

      expect(receiptListImport.reset).not.toHaveBeenCalled();
      expect(store.authStatus).toBe('authenticated');
      expect(bootstrapStore.custid).toBe(authenticatedBootstrap.custid);

      // Nor emit the applied-stream diagnostics of the session it ended.
      expect(orderingEvents()).not.toContain('session-ended');
    });

    it('a commit that loses its generation in its cleanup imports does not end a run of anomalies', async () => {
      await mountWith(authenticatedBootstrap);
      // A store only this case makes existing, so its import is still gated.
      getActivePinia()!.state.value.receipt = {};

      // One anomaly (a replay of the hydrated version) whose retry fails.
      const replay = toWire(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).replyOnce(200, replay).onGet(ENDPOINT).networkErrorOnce();
      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('failed');
      // An ended session parks in its cleanup imports, then loses the generation.
      axiosMock.onGet(ENDPOINT).replyOnce(200, toWire(newerSnapshot(anonymousBootstrap)));
      const parked = store.refresh({ kind: 'auth-mutation', reason: 'password-change' });
      await vi.advanceTimersByTimeAsync(0);
      store.stop();
      receiptImport.release();
      expect(await parked).toBe('superseded');
      // The dropped commit did not reset the count: this is the second in a row.
      axiosMock.onGet(ENDPOINT).replyOnce(200, replay);
      expect(await store.refresh({ kind: 'ordinary', reason: 'interval' })).toBe('refused');
      expect(attemptForcedPageLoad).toHaveBeenCalledTimes(1);
    });

    it('an account change still resets account-scoped stores when the commit owns its generation', async () => {
      await mountWith(authenticatedBootstrap);
      const reset = vi.spyOn(useOrganizationStore(), '$reset');
      axiosMock.onGet(ENDPOINT).reply(200, toWire(accountB));

      await store.refresh({ kind: 'auth-mutation', reason: 'account-switch' });

      expect(bootstrapStore.custid).toBe('ur-b');
      expect(reset).toHaveBeenCalledTimes(1);
    });
  });

  // -------------------------------------------------------------------------
  // one shared disposition on rejections (ADR-046#rejection-disposition)
  // -------------------------------------------------------------------------
  describe('noteApiRejection returns an explicit disposition (ADR-046#rejection-disposition)', () => {
    const revoked = { code: 'active_session_revoked', code_scope: 'customer_session' } as const;

    it('an accepted rejection returns { ownedByCoordinator: true, reason: reconciling }', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(newerSnapshot(authenticatedBootstrap)));

      expect(store.noteApiRejection(revoked)).toEqual({
        ownedByCoordinator: true,
        reason: 'reconciling',
      });
    });

    it('a throttled duplicate returns { ownedByCoordinator: false, reason: throttled }', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(newerSnapshot(authenticatedBootstrap)));

      const first = store.noteApiRejection(revoked);
      const second = store.noteApiRejection(revoked);

      expect(first.ownedByCoordinator).toBe(true);
      // A follow-up rejection within REJECTION_MIN_INTERVAL is throttled — the
      // coordinator will NOT run for it, so the caller keeps its toast
      // (ADR-046#rejection-disposition).
      expect(second).toEqual({ ownedByCoordinator: false, reason: 'throttled' });
    });

    it('an admin-only timeout returns { ownedByCoordinator: false, reason: skipped-carve-out }', async () => {
      await mountWith(authenticatedBootstrap);

      const d = store.noteApiRejection({
        code: 'admin_session_expired',
        code_scope: 'admin_session',
      });

      expect(d).toEqual({ ownedByCoordinator: false, reason: 'skipped-carve-out' });
    });

    it('awaiting_mfa on an MFA-pending tab returns skipped-carve-out', async () => {
      await mountWith(mfaPendingBootstrap);

      const d = store.noteApiRejection({ code: 'awaiting_mfa', code_scope: 'customer_session' });

      expect(d).toEqual({ ownedByCoordinator: false, reason: 'skipped-carve-out' });
    });

    it('a rejection on a tab that never held a session returns skipped-carve-out', async () => {
      await mountWith(anonymousBootstrap);

      const d = store.noteApiRejection(revoked);

      expect(d).toEqual({ ownedByCoordinator: false, reason: 'skipped-carve-out' });
    });

    it('once the tab has entered stale-session, further rejections report will-reload', async () => {
      await mountWith(authenticatedBootstrap);
      // Force the tab into stale-session by taking the forced page-load path.
      store.forcePageLoad('ended');
      expect(store.staleSession).toBe(true);

      const d = store.noteApiRejection(revoked);

      expect(d).toEqual({ ownedByCoordinator: true, reason: 'will-reload' });
    });

    it('readCoordinatorDisposition returns the disposition off a stamped error', () => {
      const err = new Error('401') as unknown as Record<string | symbol, unknown>;
      err[COORDINATOR_DISPOSITION_KEY] = { ownedByCoordinator: true, reason: 'reconciling' };

      expect(readCoordinatorDisposition(err)).toEqual({
        ownedByCoordinator: true,
        reason: 'reconciling',
      });
    });

    it('readCoordinatorDisposition returns null on an unstamped error', () => {
      expect(readCoordinatorDisposition(new Error('no stamp'))).toBeNull();
      expect(readCoordinatorDisposition(null)).toBeNull();
      expect(readCoordinatorDisposition(undefined)).toBeNull();
    });
  });

  // -------------------------------------------------------------------------
  // stale-session mode gates protected actions (ADR-046#authority-action-gating)
  // -------------------------------------------------------------------------
  describe('stale-session mode gates protected actions (ADR-046#authority-action-gating)', () => {
    it('a bounded replaced-session reload disables protected actions but keeps escapes', async () => {
      await mountWith(authenticatedBootstrap);
      expect(store.protectedActionsAvailable).toBe(true);
      vi.mocked(attemptForcedPageLoad).mockReturnValueOnce('bounded');

      store.forcePageLoad('replaced');

      expect(attemptForcedPageLoad).toHaveBeenCalledTimes(1);
      expect(store.staleSession).toBe(true);
      // authStatus is untouched by the forced page load; the gate must not
      // rely on it alone.
      expect(store.authStatus).toBe('authenticated');
      expect(store.protectedActionsAvailable).toBe(false);
      expect(store.escapeActionsAvailable).toBe(true);
    });
  });
});
