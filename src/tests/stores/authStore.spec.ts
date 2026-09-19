// src/tests/stores/authStore.spec.ts
//
// authStore holds no authentication state of its own (#4458): every accessor
// is derived from bootstrapStore.authStatus. The refresh coordinator is
// covered in authStore.coordinator.spec.ts; the account-transition rules in
// bootstrapStore.accountTransition.spec.ts.

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { _resetForTesting, getBootstrapValue } from '@/services/bootstrap.service';
import { clearDiagnosticsActorContext } from '@/services/diagnostics.service';
import { AUTH_CHECK_CONFIG, useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import {
  anonymousBootstrap,
  authenticatedBootstrap,
  mfaPendingBootstrap,
  unavailableBootstrap,
} from '@/tests/fixtures/bootstrap.fixture';
import { toWire } from '@/tests/fixtures/bootstrap-wire';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';

vi.mock('@/services/diagnostics.service', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/services/diagnostics.service')>()),
  clearDiagnosticsActorContext: vi.fn(),
  setDiagnosticsActorContext: vi.fn(),
}));

const BOOTSTRAP_KEY = '__BOOTSTRAP_ME__';
const ENDPOINT = AUTH_CHECK_CONFIG.ENDPOINT;

describe('authStore', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useAuthStore>;
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  /** Mounts the stores over a hydrated page, in app order. */
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

  afterEach(() => {
    store?.$dispose();
    axiosMock?.restore();
    vi.useRealTimers();
    vi.clearAllMocks();
    _resetForTesting();
    delete (window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY];
    sessionStorage.clear();
  });

  describe('accessors derive from the one status', () => {
    it.each([
      ['checking', null, { auth: false, full: false, mfa: false, present: false }],
      ['anonymous', anonymousBootstrap, { auth: false, full: false, mfa: false, present: false }],
      ['mfa_pending', mfaPendingBootstrap, { auth: false, full: false, mfa: true, present: true }],
      ['unavailable', unavailableBootstrap, { auth: false, full: false, mfa: false, present: false }],
      ['authenticated', authenticatedBootstrap, { auth: true, full: true, mfa: false, present: true }],
    ] as const)('%s', async (status, hydration, expected) => {
      await mountWith(hydration);

      expect(store.authStatus).toBe(status);
      expect(store.isAuthenticated).toBe(expected.auth);
      expect(store.isFullyAuthenticated).toBe(expected.full);
      expect(store.awaitingMfa).toBe(expected.mfa);
      expect(store.isUserPresent).toBe(expected.present);
    });

    it('follow the bootstrap store reactively', async () => {
      await mountWith(authenticatedBootstrap);
      expect(store.isAuthenticated).toBe(true);

      bootstrapStore.withholdAuthority('unavailable');

      expect(store.authStatus).toBe('unavailable');
      expect(store.isAuthenticated).toBe(false);
      expect(store.isFullyAuthenticated).toBe(false);
    });
  });

  describe('init', () => {
    it('is idempotent', async () => {
      await mountWith(authenticatedBootstrap);
      const timer = store.authCheckTimer;

      store.init();

      expect(store.isInitialized).toBe(true);
      expect(store.authCheckTimer).toBe(timer);
    });

    it('schedules the passive interval while authenticated', async () => {
      await mountWith(authenticatedBootstrap);
      expect(store.authCheckTimer).not.toBeNull();
    });

    it('schedules nothing for an anonymous page', async () => {
      await mountWith(anonymousBootstrap);
      expect(store.authCheckTimer).toBeNull();
    });

    it('counts a hydrated server statement as a check', async () => {
      await mountWith(anonymousBootstrap);
      expect(store.lastCheckTime).not.toBeNull();
    });

    it('does not count `checking` as a check', async () => {
      await mountWith(null);
      expect(store.lastCheckTime).toBeNull();
      expect(store.needsCheck).toBe(true);
    });

    it('reads nothing from sessionStorage', async () => {
      sessionStorage.setItem('ots_auth_state', 'true');
      const getItem = vi.spyOn(Storage.prototype, 'getItem');

      await mountWith({ ...anonymousBootstrap, had_valid_session: true });

      expect(store.isAuthenticated).toBe(false);
      expect(getItem).not.toHaveBeenCalledWith('ots_auth_state');
      getItem.mockRestore();
    });

    it('makes no request', async () => {
      await mountWith(authenticatedBootstrap);
      expect(axiosMock.history.get).toHaveLength(0);
    });
  });

  describe('logout (local, no navigation follows)', () => {
    it('ends in an explicit anonymous with no customer data', async () => {
      await mountWith(authenticatedBootstrap);

      await store.logout();

      expect(store.authStatus).toBe('anonymous');
      expect(store.isAuthenticated).toBe(false);
      expect(bootstrapStore.cust).toBeNull();
      expect(bootstrapStore.email).toBe('');
      expect(getBootstrapValue('cust')).toBeNull();
    });

    it('stops the interval, clears storage and the diagnostics actor', async () => {
      await mountWith(authenticatedBootstrap);
      sessionStorage.setItem('anything', 'x');

      await store.logout();

      expect(store.authCheckTimer).toBeNull();
      expect(sessionStorage.length).toBe(0);
      expect(clearDiagnosticsActorContext).toHaveBeenCalled();
    });

    it('resets the account-scoped stores', async () => {
      await mountWith(authenticatedBootstrap);
      const reset = vi.spyOn(useOrganizationStore(), '$reset');

      await store.logout();

      expect(reset).toHaveBeenCalledTimes(1);
    });

    it('keeps server configuration', async () => {
      await mountWith({ ...authenticatedBootstrap, locale: 'de' });
      const ui = JSON.stringify(bootstrapStore.ui);

      await store.logout();

      expect(JSON.stringify(bootstrapStore.ui)).toBe(ui);
    });

    it('setAuthenticated(false) is a local sign-out', async () => {
      await mountWith(authenticatedBootstrap);

      await store.setAuthenticated(false);

      expect(store.authStatus).toBe('anonymous');
      expect(axiosMock.history.get).toHaveLength(0);
    });
  });

  describe('setAuthenticated(true)', () => {
    it('asks the server and takes its answer', async () => {
      await mountWith(anonymousBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(authenticatedBootstrap));

      await store.setAuthenticated(true);

      expect(axiosMock.history.get).toHaveLength(1);
      expect(store.isAuthenticated).toBe(true);
      expect(store.authCheckTimer).not.toBeNull();
    });

    it('grants nothing when the server does not', async () => {
      await mountWith(anonymousBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(anonymousBootstrap));

      await store.setAuthenticated(true);

      expect(store.isAuthenticated).toBe(false);
    });

    it('grants nothing when the server cannot be reached', async () => {
      await mountWith(anonymousBootstrap);
      axiosMock.onGet(ENDPOINT).networkError();

      await store.setAuthenticated(true);

      expect(store.isAuthenticated).toBe(false);
      expect(store.authStatus).toBe('anonymous');
    });
  });

  describe('checkWindowStatus (deprecated delegate)', () => {
    it('does not ask when the status is a definitive anonymous', async () => {
      await mountWith(anonymousBootstrap);

      expect(await store.checkWindowStatus()).toBe(false);
      expect(axiosMock.history.get).toHaveLength(0);
    });

    it('otherwise goes through the coordinator', async () => {
      await mountWith(authenticatedBootstrap);
      axiosMock.onGet(ENDPOINT).reply(200, toWire(authenticatedBootstrap));

      expect(await store.checkWindowStatus()).toBe(true);
      expect(axiosMock.history.get).toHaveLength(1);
    });
  });

  describe('$dispose', () => {
    it('stops timers and the visibility listener', async () => {
      await mountWith(authenticatedBootstrap);
      const remove = vi.spyOn(document, 'removeEventListener');

      await store.$dispose();

      expect(store.authCheckTimer).toBeNull();
      expect(remove).toHaveBeenCalledWith('visibilitychange', expect.any(Function));
      remove.mockRestore();
    });
  });
});
