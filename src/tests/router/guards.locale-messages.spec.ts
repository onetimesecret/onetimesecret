// src/tests/router/guards.locale-messages.spec.ts
//
// The first navigation when the visitor's locale is one the server lists but
// this build has no messages for. The language store drops such a locale from
// the supported locales (languageStore.ts, loadSupportedLocales), so the guard
// activates the next candidate and router.isReady() resolves. Without that,
// activating it rejected, the initial navigation failed and startApp flagged
// the shell on every page (src/plugins/core/startApp.ts).
//
// Real router, real language store and real i18n: guards.routes.spec.ts mocks
// the store, so the filter is invisible there. 'sw' has no generated file.

import { setupRouterGuards } from '@/router/guards.routes';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useLanguageStore } from '@/shared/stores/languageStore';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createMemoryHistory, createRouter, type Router } from 'vue-router';
import { setupTestPinia } from '../setup';

vi.mock('@/shared/stores/authStore', () => ({
  useAuthStore: vi.fn(() => ({
    authStatus: 'anonymous',
    isAuthenticated: false,
    isFullyAuthenticated: false,
    awaitingMfa: false,
    refresh: vi.fn(),
  })),
}));

vi.mock('@/shared/composables/usePageTitle', () => ({
  usePageTitle: vi.fn(() => ({
    setTitle: vi.fn(),
    useComputedTitle: vi.fn(),
    formatTitle: vi.fn(),
  })),
}));

vi.mock('@/utils/features', () => ({
  isSsoOnlyMode: vi.fn(() => false),
}));

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: vi.fn(),
}));

vi.mock('@/shared/stores/notificationsStore', () => ({
  useNotificationsStore: vi.fn(() => ({
    show: vi.fn(),
    enqueue: vi.fn(),
    isVisible: false,
  })),
}));

const View = { render: () => null };

function makeRouter(): Router {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', name: 'Home', component: View },
      { path: '/about', name: 'About', component: View },
      { path: '/:pathMatch(.*)*', name: 'NotFound', component: View },
    ],
  });
  setupRouterGuards(router);
  // Registered so vue-router hands a failed navigation's error to isReady()
  // below instead of printing it.
  router.onError(() => undefined);
  return router;
}

/** Runs the initial navigation; resolves with the isReady() outcome. */
async function startAt(router: Router, path: string): Promise<'ready' | Error> {
  router.push(path).catch(() => undefined);
  return router.isReady().then(
    () => 'ready' as const,
    (error: Error) => error
  );
}

describe('first navigation with a supported locale that has no messages in this build', () => {
  beforeEach(async () => {
    // init() is called below with the device locale, as the app does.
    await setupTestPinia({ autoInit: false });
    useBootstrapStore().update({
      supported_locales: ['en', 'sw', 'nl'],
      default_locale: 'sw',
      cust: null,
    });
    sessionStorage.clear();
  });

  it('starts in the next locale that has messages instead of failing', async () => {
    const languageStore = useLanguageStore();
    languageStore.init({ deviceLocale: 'sw' });
    const router = makeRouter();

    expect(await startAt(router, '/about')).toBe('ready');

    expect(languageStore.currentLocale).toBe('en');
  });

  it('ignores a ?locale= naming it, like an unsupported one', async () => {
    const languageStore = useLanguageStore();
    languageStore.init({ deviceLocale: 'nl' });
    const router = makeRouter();

    expect(await startAt(router, '/about?locale=sw')).toBe('ready');

    expect(languageStore.currentLocale).toBe('nl');
  });
});
