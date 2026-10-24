import { globalComposer } from '@/i18n';
import { setupRouterGuards } from '@/router/guards.routes';
import type { ClientAuthStatus } from '@/schemas/contracts/bootstrap';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { PREFERENCE_SAVE_TIMEOUT_MS, useLanguageStore } from '@/shared/stores/languageStore';
import { mockCustomer } from '@/tests/fixtures/bootstrap.fixture';
import { setupTestPinia } from '@/tests/setup';
import { captureAppLogs } from '@/tests/utils/appLogs';
import { handlePreloadError } from '@/utils/preloadError';
import { flushPromises } from '@vue/test-utils';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createMemoryHistory, createRouter } from 'vue-router';

const control = vi.hoisted(() => ({
  authenticated: true,
  failing: false,
  status: null as ClientAuthStatus | null,
  refresh: vi.fn(),
}));
vi.mock('@/shared/stores/authStore', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/shared/stores/authStore')>()),
  useAuthStore: () => ({
    get authStatus() {
      return control.status ?? (control.authenticated ? 'authenticated' : 'anonymous');
    },
    get isFullyAuthenticated() {
      return control.authenticated;
    },
    get isAuthenticated() {
      return control.authenticated;
    },
    awaitingMfa: false,
    refresh: control.refresh,
  }),
}));
vi.mock('@/shared/composables/usePageTitle', () => ({
  usePageTitle: () => ({ setTitle: vi.fn() }),
}));
vi.mock('@/i18n', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/i18n')>();
  return {
    ...actual,
    setGlobalLocale: (locale: string, options?: Parameters<typeof actual.setGlobalLocale>[1]) => {
      if (locale === 'nl' && control.failing) {
        const error = new Error('chunk nl failed');
        const event = new Event('vite:preloadError');
        (event as Event & { payload: Error }).payload = error;
        window.dispatchEvent(event);
        return Promise.reject(error);
      }
      return actual.setGlobalLocale(locale, options);
    },
  };
});

const KEY = 'selected.locale.pending-update';
const View = { render: () => null };

function seedPending(overrides: Record<string, unknown> = {}) {
  sessionStorage.setItem(
    KEY,
    JSON.stringify({
      id: 'pending-test',
      locale: 'nl',
      accountExtid: mockCustomer.extid,
      createdAt: Date.now(),
      ...overrides,
    })
  );
}

async function startAt(path: string) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', name: 'Home', component: View },
      { path: '/dashboard', name: 'Dashboard', component: View, meta: { requiresAuth: true } },
      { path: '/other', component: View, meta: { requiresAuth: true } },
      { path: '/about', component: View },
      { path: '/signin', name: 'Sign In', component: View },
    ],
  });
  await setupRouterGuards(router);
  await router.push(path);
  await router.isReady();
  // A resumed save runs behind the navigation; let an answered one settle.
  await flushPromises();
  return router;
}

async function boot() {
  const setup = await setupTestPinia({ autoInit: false });
  useBootstrapStore().update({
    supported_locales: ['en', 'nl', 'de'],
    default_locale: 'en',
    cust: control.authenticated ? { ...mockCustomer, locale: 'en' } : null,
  });
  useLanguageStore().init();
  return setup.axiosMock!;
}

describe('resuming an interrupted language preference update', () => {
  let api: AxiosMockAdapter;
  const reload = vi.fn();
  let bounded = false;
  const onPreloadError = (event: Event) =>
    handlePreloadError(event, {
      reload,
      now: Date.now(),
      storage: { getItem: () => (bounded ? String(Date.now()) : null), setItem: vi.fn() },
    });

  beforeEach(async () => {
    control.authenticated = true;
    control.failing = false;
    control.status = null;
    control.refresh.mockReset();
    bounded = false;
    reload.mockReset();
    sessionStorage.clear();
    globalComposer.locale.value = 'en';
    api = await boot();
    window.addEventListener('vite:preloadError', onPreloadError);
  });
  afterEach(() => {
    window.removeEventListener('vite:preloadError', onPreloadError);
    vi.restoreAllMocks();
  });

  it('carries the original choice across a reload and saves it before account locale selection', async () => {
    const store = useLanguageStore();
    await store.setCurrentLocale('en');
    control.failing = true;
    await expect(store.updateLanguage('nl')).rejects.toThrow('chunk nl failed');
    expect(reload).toHaveBeenCalledOnce();
    expect(api.history.post).toHaveLength(0);
    expect(sessionStorage.getItem(KEY)).not.toBeNull();

    control.failing = false;
    api = await boot();
    api.onPost('/api/account/update-locale', { locale: 'nl' }).reply(200, {});
    const router = await startAt('/dashboard');

    expect(useLanguageStore().currentLocale).toBe('nl');
    expect(useBootstrapStore().cust?.locale).toBe('nl');
    expect(api.history.post).toHaveLength(1);
    expect(sessionStorage.getItem(KEY)).toBeNull();
    await router.push('/other');
    expect(useLanguageStore().currentLocale).toBe('nl');
    expect(api.history.post).toHaveLength(1);
  });

  it('records the operation before the chunk handler invokes reload', async () => {
    control.failing = true;
    let recorded: string | null = null;
    reload.mockImplementationOnce(() => {
      recorded = sessionStorage.getItem(KEY);
    });
    await expect(useLanguageStore().updateLanguage('nl')).rejects.toThrow();
    expect(reload).toHaveBeenCalledOnce();
    expect(JSON.parse(recorded!)).toMatchObject({ locale: 'nl', accountExtid: mockCustomer.extid });
  });

  it.each([200, 500])(
    'preserves the active switch POST outcome (%s) when a newer switch fails to load',
    async (status) => {
      captureAppLogs();
      const router = await startAt('/dashboard');
      const store = useLanguageStore();
      let finish!: (response: [number, object]) => void;
      api.onPost('/api/account/update-locale', { locale: 'de' }).reply(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          })
      );
      const saving = store.updateLanguage('de');
      await vi.waitFor(() => expect(finish).toBeTypeOf('function'));
      expect(store.currentLocale).toBe('de');
      const outcome = saving.catch((error: unknown) => error);
      control.failing = true;
      bounded = true;
      await expect(store.updateLanguage('nl')).rejects.toThrow('chunk nl failed');
      finish([status, {}]);
      await outcome;
      expect(store.currentLocale).toBe('de');
      if (status === 200) {
        expect(useBootstrapStore().cust?.locale).toBe('de');
        await router.push('/other');
        expect(store.currentLocale).toBe('de');
      } else {
        store.dismissLocaleLoadFailure();
        expect(store.localeSaveFailure).toEqual({ locale: 'de', accountExtid: mockCustomer.extid });
      }
    }
  );

  it.each(['unavailable', 'mfa_pending'] as const)(
    'does not replay an anonymous operation when auth is %s',
    async (status) => {
      seedPending({ accountExtid: null });
      control.authenticated = false;
      control.status = status;
      useBootstrapStore().update({ cust: null });
      await startAt('/about');
      expect(api.history.post).toHaveLength(0);
      expect(sessionStorage.getItem(KEY)).toBeNull();
    }
  );

  it('resumes on a public page too', async () => {
    seedPending();
    api.onPost('/api/account/update-locale').reply(200, {});
    await startAt('/about');
    expect(useLanguageStore().currentLocale).toBe('nl');
    expect(api.history.post).toHaveLength(1);
  });

  it('resumes once across an initial redirect', async () => {
    seedPending();
    api.onPost('/api/account/update-locale').reply(200, {});
    const router = await startAt('/');
    expect(router.currentRoute.value.path).toBe('/dashboard');
    expect(useLanguageStore().currentLocale).toBe('nl');
    expect(api.history.post).toHaveLength(1);
  });

  it('consumes the attempt when the chunk fails again, without saving or reloading again', async () => {
    captureAppLogs();
    seedPending();
    control.failing = true;
    bounded = true;
    await startAt('/dashboard');
    expect(useLanguageStore().currentLocale).toBe('en');
    expect(useLanguageStore().localeLoadFailure).toEqual({ requested: 'nl', shown: 'en' });
    expect(sessionStorage.getItem(KEY)).toBeNull();
    expect(api.history.post).toHaveLength(0);
    expect(reload).not.toHaveBeenCalled();
  });

  it.each([
    ['expired', { createdAt: Date.now() - 10 * 60_000 }],
    ['future', { createdAt: Date.now() + 10 * 60_000 }],
    ['unsupported', { locale: 'sw' }],
    ['different account', { accountExtid: 'someone-else' }],
    ['anonymous operation on a signed-in account', { accountExtid: null }],
    ['malformed timestamp', { createdAt: 'yesterday' }],
  ])('discards an %s operation', async (_name, overrides) => {
    seedPending(overrides);
    await startAt('/dashboard');
    expect(useLanguageStore().currentLocale).toBe('en');
    expect(api.history.post).toHaveLength(0);
    expect(sessionStorage.getItem(KEY)).toBeNull();
  });

  it('discards malformed JSON', async () => {
    sessionStorage.setItem(KEY, '{');
    await startAt('/dashboard');
    expect(api.history.post).toHaveLength(0);
    expect(sessionStorage.getItem(KEY)).toBeNull();
  });

  it('does not apply an account operation after signout', async () => {
    seedPending();
    control.authenticated = false;
    useBootstrapStore().update({ cust: null });
    await startAt('/about');
    expect(api.history.post).toHaveLength(0);
    expect(sessionStorage.getItem(KEY)).toBeNull();
  });

  it('resumes an anonymous session preference only while still anonymous', async () => {
    seedPending({ accountExtid: null });
    control.authenticated = false;
    useBootstrapStore().update({ cust: null });
    api.onPost('/api/account/update-locale').reply(200, {});
    await startAt('/about');
    expect(useLanguageStore().currentLocale).toBe('nl');
    expect(useBootstrapStore().cust).toBeNull();
    expect(api.history.post).toHaveLength(1);
  });

  it('lets a conflicting explicit URL locale cancel recovery', async () => {
    seedPending();
    await startAt('/dashboard?locale=de');
    expect(useLanguageStore().currentLocale).toBe('de');
    expect(api.history.post).toHaveLength(0);
    expect(sessionStorage.getItem(KEY)).toBeNull();
  });

  it('still saves when the explicit URL locale agrees', async () => {
    seedPending();
    api.onPost('/api/account/update-locale').reply(200, {});
    await startAt('/dashboard?locale=nl');
    expect(useBootstrapStore().cust?.locale).toBe('nl');
    expect(api.history.post).toHaveLength(1);
  });

  it('does not attempt a matching failed URL locale twice', async () => {
    captureAppLogs();
    seedPending();
    control.failing = true;
    bounded = true;
    const activate = vi.spyOn(useLanguageStore(), 'setCurrentLocale');
    await startAt('/dashboard?locale=nl');
    expect(activate.mock.calls.filter(([locale]) => locale === 'nl')).toHaveLength(1);
    expect(api.history.post).toHaveLength(0);
    expect(sessionStorage.getItem(KEY)).toBeNull();
  });

  it('keeps the activated language and offers explicit retry when saving fails', async () => {
    captureAppLogs();
    seedPending();
    api.onPost('/api/account/update-locale').networkError();
    await startAt('/dashboard');
    const store = useLanguageStore();
    expect(store.currentLocale).toBe('nl');
    expect(store.localeLoadFailure).toBeNull();
    expect(store.localeSaveFailure).toEqual({ locale: 'nl', accountExtid: mockCustomer.extid });
    expect(sessionStorage.getItem(KEY)).toBeNull();

    api.onPost('/api/account/update-locale').reply(200, {});
    await store.retryLanguageSave();
    expect(store.localeSaveFailure).toBeNull();
    expect(useBootstrapStore().cust?.locale).toBe('nl');
    expect(api.history.post).toHaveLength(2);
  });

  it('does not hold the initial navigation for the resumed save', async () => {
    seedPending();
    let finish!: (response: [number, object]) => void;
    api.onPost('/api/account/update-locale').reply(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        })
    );
    const router = await startAt('/dashboard');
    const store = useLanguageStore();
    expect(store.currentLocale).toBe('nl');
    expect(api.history.post).toHaveLength(1);
    expect(api.history.post[0].timeout).toBe(PREFERENCE_SAVE_TIMEOUT_MS);
    expect(useBootstrapStore().cust?.locale).toBe('en');
    expect(store.savingLocale).toBe('nl');

    // The snapshot still names the old account locale; the pending save wins.
    await router.push('/other');
    expect(store.currentLocale).toBe('nl');

    finish([200, {}]);
    await flushPromises();
    expect(useBootstrapStore().cust?.locale).toBe('nl');
    expect(store.savingLocale).toBeNull();
  });

  it.each([
    [200, 'de'],
    [500, 'en'],
  ])(
    'keeps a toggled language across protected navigation while its save is pending (%s)',
    async (status, afterwards) => {
      captureAppLogs();
      const router = await startAt('/dashboard');
      const store = useLanguageStore();
      let finish!: (response: [number, object]) => void;
      api.onPost('/api/account/update-locale').reply(
        () =>
          new Promise((resolve) => {
            finish = resolve;
          })
      );
      const switching = store.updateLanguage('de').catch(() => undefined);
      await vi.waitFor(() => expect(finish).toBeTypeOf('function'));

      await router.push('/other');
      expect(store.currentLocale).toBe('de');

      finish([status, {}]);
      await switching;
      expect(store.savingLocale).toBeNull();
      // A failed save leaves the server's locale as the account's again.
      await router.push('/dashboard');
      expect(store.currentLocale).toBe(afterwards);
    }
  );

  it('sends a newer choice only after a pending retry settles, so the newer one is saved', async () => {
    captureAppLogs();
    seedPending();
    api.onPost('/api/account/update-locale').networkErrorOnce();
    await startAt('/dashboard');
    const store = useLanguageStore();
    expect(store.localeSaveFailure).toEqual({ locale: 'nl', accountExtid: mockCustomer.extid });

    let finish!: (response: [number, object]) => void;
    api.onPost('/api/account/update-locale', { locale: 'nl' }).reply(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        })
    );
    api.onPost('/api/account/update-locale', { locale: 'de' }).reply(200, {});
    const retrying = store.retryLanguageSave();
    await vi.waitFor(() => expect(finish).toBeTypeOf('function'));
    const switching = store.updateLanguage('de');
    await vi.waitFor(() => expect(store.currentLocale).toBe('de'));
    await flushPromises();
    expect(api.history.post).toHaveLength(2);

    finish([200, {}]);
    await Promise.all([retrying, switching]);
    expect(api.history.post.map((request) => JSON.parse(request.data).locale)).toEqual([
      'nl',
      'nl',
      'de',
    ]);
    expect(useBootstrapStore().cust?.locale).toBe('de');
    expect(store.localeSaveFailure).toBeNull();
  });
});
