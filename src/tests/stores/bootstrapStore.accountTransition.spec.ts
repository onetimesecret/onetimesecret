// src/tests/stores/bootstrapStore.accountTransition.spec.ts
//
// #4458: the bootstrap store is the one writable authentication authority.
//
// These specs use the REAL bootstrap.service (no vi.mock) because the
// pre-Pinia mirror is one of the places a previous account's data could
// survive, and that is exactly what is being proven here.

import { bootstrapSchema, type BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { _resetForTesting, getBootstrapValue } from '@/services/bootstrap.service';
import { ACCOUNT_SCOPED_KEYS, useBootstrapStore } from '@/shared/stores/bootstrapStore';
import {
  anonymousBootstrap,
  authenticatedBootstrap,
  mfaPendingBootstrap,
  mockCustomer,
  unavailableBootstrap,
} from '@/tests/fixtures/bootstrap.fixture';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@/services/diagnostics.service', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/services/diagnostics.service')>()),
  setDiagnosticsActorContext: vi.fn(),
}));

import { setDiagnosticsActorContext } from '@/services/diagnostics.service';

const BOOTSTRAP_KEY = '__BOOTSTRAP_ME__';

function hydrate(payload: unknown): void {
  (window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY] = payload;
}

/** Every fixture goes through the contract, as a real payload would. */
function snapshot(payload: BootstrapPayload): BootstrapPayload {
  return bootstrapSchema.parse(payload);
}

/** Account A: carries every kind of account-scoped field. */
const accountA: BootstrapPayload = {
  ...authenticatedBootstrap,
  apitoken: 'token-of-account-a',
  customer_since: 'Mar 21, 2026',
  custom_domains: ['a.example.com'],
  domain_context: 'a.example.com',
  has_password: true,
  entitlement_preview_planid: 'identity_plus_v1',
  entitlement_preview_plan_name: 'Identity Plus',
  diagnostics_ref: { actor_ref: 'a1b2c3d4e5f60718' },
  organization: { objid: 'org-a-objid', extid: 'org-a', display_name: 'Org of A', is_default: true },
  stripe_customer: { id: 'cus_A' } as BootstrapPayload['stripe_customer'],
  stripe_subscriptions: [{ id: 'sub_A' }] as BootstrapPayload['stripe_subscriptions'],
};

/** Account B: a different customer whose payload OMITS most of those fields. */
const accountB: BootstrapPayload = {
  ...authenticatedBootstrap,
  cust: { ...mockCustomer, objid: 'cust-b', extid: 'ur-b', email: 'b@example.com' },
  custid: 'ur-b',
  email: 'b@example.com',
};

describe('bootstrapStore: single authentication authority (#4458)', () => {
  let store: ReturnType<typeof useBootstrapStore>;

  beforeEach(() => {
    _resetForTesting();
    delete (window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY];
    setActivePinia(createPinia());
    store = useBootstrapStore();
    vi.mocked(setDiagnosticsActorContext).mockClear();
  });

  afterEach(() => {
    _resetForTesting();
    delete (window as unknown as Record<string, unknown>)[BOOTSTRAP_KEY];
  });

  describe('hydration (#4456)', () => {
    it('missing hydration is `checking`, never anonymous', () => {
      store.init();

      expect(store.authStatus).toBe('checking');
      expect(store.authStatus).not.toBe('anonymous');
      expect(store.isInitialized).toBe(true);
    });

    it('a valid authenticated hydration is authenticated synchronously', () => {
      hydrate(authenticatedBootstrap);
      store.init();

      expect(store.authStatus).toBe('authenticated');
      expect(store.authenticated).toBe(true);
      expect(store.cust?.extid).toBe(mockCustomer.extid);
    });

    it.each([
      ['anonymous', anonymousBootstrap],
      ['mfa_pending', mfaPendingBootstrap],
      ['unavailable', unavailableBootstrap],
    ] as const)('a valid %s hydration is taken at its word', (status, payload) => {
      hydrate(payload);
      store.init();

      expect(store.authStatus).toBe(status);
      expect(store.authenticated).toBe(false);
      expect(store.cust).toBeNull();
    });

    it('invalid hydration is `checking`: config kept, identity withheld', () => {
      // `shrimp: null` fails the contract (`.default('')` rejects null).
      hydrate({ ...accountA, locale: 'fr', shrimp: null });
      store.init();

      expect(store.authStatus).toBe('checking');
      expect(store.authenticated).toBe(false);
      // The page still renders in the right locale...
      expect(store.locale).toBe('fr');
      // ...but a payload that failed the contract says nothing about identity.
      expect(store.cust).toBeNull();
      expect(store.custid).toBe('');
      expect(store.email).toBe('');
      expect(store.apitoken).toBeUndefined();
      expect(store.organization).toBeUndefined();
      expect(getBootstrapValue('cust')).toBeNull();
      expect(getBootstrapValue('apitoken')).toBeUndefined();
    });

    it('a payload whose status and projections disagree can only withhold', () => {
      hydrate({ ...accountA, auth_status: 'anonymous' });
      store.init();

      expect(store.authStatus).toBe('anonymous');
      expect(store.authenticated).toBe(false);
      expect(store.cust).toBeNull();
      expect(store.apitoken).toBeUndefined();
    });
  });

  describe('account transition', () => {
    it('A -> B clears every account-scoped field that B omits', () => {
      store.applySnapshot(snapshot(accountA));
      expect(store.apitoken).toBe('token-of-account-a');
      expect(store.organization).toBeDefined();

      store.applySnapshot(snapshot(accountB));

      expect(store.authStatus).toBe('authenticated');
      expect(store.custid).toBe('ur-b');
      expect(store.email).toBe('b@example.com');

      expect(store.apitoken).toBeUndefined();
      expect(store.customer_since).toBeUndefined();
      expect(store.organization).toBeUndefined();
      expect(store.stripe_customer).toBeUndefined();
      expect(store.stripe_subscriptions).toBeUndefined();
      expect(store.entitlement_preview_planid).toBeUndefined();
      expect(store.entitlement_preview_plan_name).toBeUndefined();
      expect(store.diagnostics_ref).toBeUndefined();
      expect(store.custom_domains).toEqual([]);
      expect(store.domain_context).toBeNull();
    });

    it('A -> B leaves nothing of A in the pre-Pinia mirror either', () => {
      store.applySnapshot(snapshot(accountA));
      expect(getBootstrapValue('apitoken')).toBe('token-of-account-a');

      store.applySnapshot(snapshot(accountB));

      expect(getBootstrapValue('apitoken')).toBeUndefined();
      expect(getBootstrapValue('organization')).toBeUndefined();
      expect(getBootstrapValue('stripe_customer')).toBeUndefined();
      expect(getBootstrapValue('diagnostics_ref')).toBeUndefined();
      expect(getBootstrapValue('custid')).toBe('ur-b');
    });

    it('nothing in the serialized state still mentions account A', () => {
      store.applySnapshot(snapshot(accountA));
      store.applySnapshot(snapshot(accountB));

      const serialized = JSON.stringify(store.$state);
      for (const trace of ['token-of-account-a', 'org-a', 'cus_A', 'sub_A', 'a1b2c3d4e5f60718', 'a.example.com']) {
        expect(serialized).not.toContain(trace);
      }
    });

    it('moves the diagnostics actor context with the account', () => {
      store.applySnapshot(snapshot(accountA));
      expect(setDiagnosticsActorContext).toHaveBeenLastCalledWith(accountA.diagnostics_ref);

      store.applySnapshot(snapshot(accountB));
      expect(setDiagnosticsActorContext).toHaveBeenLastCalledWith(null);
    });

    it('has_password: null keeps the known value for the SAME account only', () => {
      store.applySnapshot(snapshot(accountA));
      expect(store.has_password).toBe(true);

      store.applySnapshot(snapshot({ ...accountA, has_password: null }));
      expect(store.has_password).toBe(true);

      store.applySnapshot(snapshot({ ...accountB, has_password: null }));
      expect(store.has_password).toBeNull();
    });
  });

  describe('loss of authority', () => {
    it.each([
      ['anonymous', anonymousBootstrap],
      ['mfa_pending', mfaPendingBootstrap],
      ['unavailable', unavailableBootstrap],
    ] as const)('%s after authenticated removes all customer data', (status, payload) => {
      store.applySnapshot(snapshot(accountA));
      store.applySnapshot(snapshot(payload));

      const defaults = bootstrapSchema.parse({}) as Record<string, unknown>;
      const state = store.$state as unknown as Record<string, unknown>;
      expect(store.authStatus).toBe(status);
      for (const key of ACCOUNT_SCOPED_KEYS) {
        expect(state[key], key).toEqual(defaults[key]);
      }
    });

    it('withholds identity even when a non-authenticated payload carries it', () => {
      // Not something a current server sends; the client must not depend on that.
      store.applySnapshot(snapshot({ ...accountA, auth_status: 'mfa_pending', authenticated: false }));

      expect(store.authStatus).toBe('mfa_pending');
      expect(store.cust).toBeNull();
      expect(store.email).toBe('');
      expect(store.apitoken).toBeUndefined();
    });

    it('a rejection is not reversed by a local patch', () => {
      store.applySnapshot(snapshot(accountA));
      store.applySnapshot(snapshot(anonymousBootstrap));

      const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
      store.update({ authenticated: true, auth_status: 'authenticated', awaiting_mfa: false });
      warn.mockRestore();

      expect(store.authStatus).toBe('anonymous');
      expect(store.authenticated).toBe(false);
      expect(store.auth_status).toBe('anonymous');
    });

    it('a rejection is not reversed by had_valid_session', () => {
      store.applySnapshot(snapshot({ ...anonymousBootstrap, had_valid_session: true }));

      expect(store.authStatus).toBe('anonymous');
      expect(store.authenticated).toBe(false);
    });

    it('a rejection is not reversed by anything in sessionStorage', () => {
      sessionStorage.setItem('ots_auth_state', 'true');
      const getItem = vi.spyOn(Storage.prototype, 'getItem');

      hydrate({ ...anonymousBootstrap, had_valid_session: true });
      store.init();

      expect(store.authStatus).toBe('anonymous');
      expect(getItem).not.toHaveBeenCalledWith('ots_auth_state');
      getItem.mockRestore();
      sessionStorage.clear();
    });

    it('withholdAuthority changes the status and nothing else', () => {
      store.applySnapshot(snapshot(accountA));
      const before = JSON.stringify({ ...store.$state, authStatus: null });

      store.withholdAuthority('unavailable');

      expect(store.authStatus).toBe('unavailable');
      expect(JSON.stringify({ ...store.$state, authStatus: null })).toBe(before);
    });

    it('resetForLogout is an explicit anonymous, in the store and the mirror', () => {
      store.applySnapshot(snapshot({ ...accountA, locale: 'de' }));
      store.resetForLogout();

      expect(store.authStatus).toBe('anonymous');
      expect(store.cust).toBeNull();
      expect(getBootstrapValue('cust')).toBeNull();
      expect(getBootstrapValue('apitoken')).toBeUndefined();
      expect(getBootstrapValue('has_password')).toBe(false);
    });
  });

  describe('update() is a local patch', () => {
    it('merges ordinary fields', () => {
      store.applySnapshot(snapshot(accountA));
      store.update({ locale: 'es' });

      expect(store.locale).toBe('es');
      expect(getBootstrapValue('locale')).toBe('es');
      expect(store.authStatus).toBe('authenticated');
    });

    it('cannot grant authority from `checking`', () => {
      store.init();
      const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
      store.update({ authenticated: true, cust: mockCustomer });
      warn.mockRestore();

      expect(store.authStatus).toBe('checking');
      expect(store.authenticated).toBe(false);
    });
  });
});
