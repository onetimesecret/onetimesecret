// src/tests/apps/session/views/Login.spec.ts

/**
 * Login View Tests - Auth Error Handling
 *
 * Tests the error display functionality when users are redirected back
 * to the login page with an auth_error query parameter (e.g., after
 * SSO failure or magic link expiration).
 *
 * Error codes map to i18n keys in locales/content/en/session-auth.json:
 * - sso_failed -> web.login.errors.sso_failed
 * - token_missing -> web.login.errors.token_missing
 * - token_expired -> web.login.errors.token_expired
 * - token_invalid -> web.login.errors.token_invalid
 * - invalid_email -> web.login.errors.invalid_email
 *
 * Unrecognized codes fall back to the generic sso_failed message so the page
 * never renders blank (issue #3478 — the "frozen loading screen").
 */

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { createRouter, createMemoryHistory, Router } from 'vue-router';
import { nextTick, defineComponent } from 'vue';
import Login from '@/apps/session/views/Login.vue';
import { SIGNIN_VERIFIED_STATE_KEY } from '@/shared/constants/signin';
import { createTestI18n } from '@tests/setup';

// Mock child components to isolate Login view testing
vi.mock('@/apps/session/components/AuthMethodSelector.vue', () => ({
  default: defineComponent({
    name: 'AuthMethodSelector',
    // Expose initialMode so tests can assert the password-tab default is passed.
    props: ['locale', 'initialMode'],
    template:
      '<div data-testid="auth-method-selector" :data-initial-mode="initialMode">AuthMethodSelector</div>',
  }),
}));

vi.mock('@/apps/session/components/AuthView.vue', () => ({
  default: defineComponent({
    name: 'AuthView',
    // Render named slots to allow testing slot content
    template: `<div data-testid="auth-view">
      <slot name="form" />
      <slot name="footer" />
      <slot />
    </div>`,
    props: ['heading', 'headingId', 'withSubheading', 'hideIcon', 'hideBackgroundIcon', 'showReturnHome'],
  }),
}));

// Mock feature detection
vi.mock('@/utils/features', () => ({
  hasPasswordlessMethods: () => false,
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon-name="name" />',
    props: ['collection', 'name', 'size'],
  },
}));

// Mock stores
vi.mock('@/shared/stores/languageStore', () => ({
  useLanguageStore: () => ({
    currentLocale: 'en',
  }),
}));

const i18n = createTestI18n();

describe('Login.vue auth_error handling', () => {
  let router: Router;
  let wrapper: VueWrapper;

  const createWrapper = async (
    query: Record<string, string> = {},
    initialState: Record<string, unknown> = {},
    historyState: Record<string, unknown> | null = null
  ) => {
    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/signin', name: 'signin', component: Login },
        { path: '/signup', name: 'signup', component: { template: '<div />' } },
      ],
    });

    await router.push({ path: '/signin', query });
    await router.isReady();

    // The post-verification signal arrives via browser History state (as
    // useAuth.verifyAccount hands it over — window.history.state, never the
    // URL). Memory history does not touch window.history, so seed it directly;
    // the afterEach hook clears it between cases.
    if (historyState) {
      window.history.replaceState(historyState, '');
    }

    return mount(Login, {
      global: {
        plugins: [
          router,
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
            stubActions: false,
            initialState,
          }),
        ],
        stubs: {
          teleport: true,
        },
      },
    });
  };

  afterEach(() => {
    wrapper?.unmount();
    // window.history is shared across tests in the jsdom environment; reset the
    // handed-over verified flag so it never bleeds into the next case.
    window.history.replaceState(null, '');
  });

  describe('error code handling', () => {
    it('displays SSO error when auth_error=sso_failed', async () => {
      wrapper = await createWrapper({ auth_error: 'sso_failed' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('web.login.errors.sso_failed');
    });

    it('displays token expired error', async () => {
      wrapper = await createWrapper({ auth_error: 'token_expired' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('web.login.errors.token_expired');
    });

    it('displays token missing error', async () => {
      wrapper = await createWrapper({ auth_error: 'token_missing' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('web.login.errors.token_missing');
    });

    it('displays token invalid error', async () => {
      wrapper = await createWrapper({ auth_error: 'token_invalid' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('web.login.errors.token_invalid');
    });

    it('displays invalid_email error from SSO (issue #3478)', async () => {
      wrapper = await createWrapper({ auth_error: 'invalid_email' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('web.login.errors.invalid_email');
    });

    it('shows a generic error for unknown codes (never a blank page)', async () => {
      // Regression guard for issue #3478: an auth_error code this bundle does
      // not recognize (e.g. from a backend newer than the deployed frontend)
      // must still render an error rather than a silent/frozen page.
      wrapper = await createWrapper({ auth_error: 'unknown_error_code' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('web.login.errors.sso_failed');
    });

    it('does not display error when no auth_error param', async () => {
      wrapper = await createWrapper({});
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(false);
    });
  });

  describe('query param cleanup', () => {
    it('removes auth_error from URL after displaying', async () => {
      wrapper = await createWrapper({ auth_error: 'sso_failed' });
      await flushPromises();
      await nextTick();

      // Give router time to update
      await new Promise((resolve) => setTimeout(resolve, 10));

      expect(router.currentRoute.value.query.auth_error).toBeUndefined();
    });

    it('preserves other query params when clearing auth_error', async () => {
      wrapper = await createWrapper({
        auth_error: 'sso_failed',
        redirect: '/dashboard',
      });
      await flushPromises();
      await nextTick();

      // Give router time to update
      await new Promise((resolve) => setTimeout(resolve, 10));

      expect(router.currentRoute.value.query.auth_error).toBeUndefined();
      expect(router.currentRoute.value.query.redirect).toBe('/dashboard');
    });

    it('preserves email param when clearing auth_error', async () => {
      wrapper = await createWrapper({
        auth_error: 'token_expired',
        email: 'user@example.com',
      });
      await flushPromises();
      await nextTick();

      await new Promise((resolve) => setTimeout(resolve, 10));

      expect(router.currentRoute.value.query.auth_error).toBeUndefined();
      expect(router.currentRoute.value.query.email).toBe('user@example.com');
    });
  });

  describe('error display styling', () => {
    it('uses alert role for accessibility', async () => {
      wrapper = await createWrapper({ auth_error: 'sso_failed' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
    });
  });

  // ---------------------------------------------------------------------
  // Per-domain sign-in disable (#3415)
  //
  // features.signin is the resolved availability for the current domain
  // context (AND of global AUTH_SIGNIN and the domain SigninConfig). An
  // explicit false renders a friendly "not available" panel instead of
  // the auth form; true or absent (older backends) renders the form.
  // ---------------------------------------------------------------------

  describe('per-domain sign-in disabled (features.signin === false)', () => {
    const disabledState = { bootstrap: { features: { signin: false } } };

    it('renders the disabled panel instead of the auth form', async () => {
      wrapper = await createWrapper({}, disabledState);
      await flushPromises();

      expect(wrapper.find('[data-testid="signin-disabled-panel"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="auth-method-selector"]').exists()).toBe(false);
    });

    it('shows the not-available message', async () => {
      wrapper = await createWrapper({}, disabledState);
      await flushPromises();

      expect(wrapper.text()).toContain('web.login.signin_disabled_message');
    });

    it('switches the page heading and enables the return-home affordance', async () => {
      wrapper = await createWrapper({}, disabledState);
      await flushPromises();

      const authView = wrapper.findComponent({ name: 'AuthView' });
      expect(authView.props('heading')).toBe('web.login.signin_disabled_heading');
      expect(authView.props('showReturnHome')).toBe(true);
    });

    it('hides the footer sign-in options', async () => {
      wrapper = await createWrapper({}, disabledState);
      await flushPromises();

      expect(wrapper.find('nav[aria-label="Additional sign-in options"]').exists()).toBe(false);
    });

    it('renders the auth form when features.signin is true', async () => {
      wrapper = await createWrapper({}, { bootstrap: { features: { signin: true } } });
      await flushPromises();

      expect(wrapper.find('[data-testid="auth-method-selector"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="signin-disabled-panel"]').exists()).toBe(false);

      const authView = wrapper.findComponent({ name: 'AuthView' });
      expect(authView.props('showReturnHome')).toBe(false);
    });

    it('renders the auth form when features.signin is absent (older backends)', async () => {
      wrapper = await createWrapper({});
      await flushPromises();

      expect(wrapper.find('[data-testid="auth-method-selector"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="signin-disabled-panel"]').exists()).toBe(false);
    });
  });

  // ---------------------------------------------------------------------
  // Post-verification return (browser History state)
  //
  // After clicking the link in the welcome email, useAuth.verifyAccount()
  // sends the user here with a one-shot "verified" flag in window.history
  // .state (SIGNIN_VERIFIED_STATE_KEY), never the URL. The page shows a
  // persistent success banner (rather than relying on the transient toast)
  // and defaults the auth UI to the password tab so the user re-enters the
  // password they just chose during signup.
  // ---------------------------------------------------------------------

  describe('post-verification return (history state)', () => {
    const verifiedState = { [SIGNIN_VERIFIED_STATE_KEY]: true };

    it('shows the persistent verified success banner', async () => {
      wrapper = await createWrapper({}, {}, verifiedState);
      await flushPromises();

      const notice = wrapper.find('[data-testid="signin-verified-notice"]');
      expect(notice.exists()).toBe(true);
      expect(notice.text()).toContain('web.login.verified_notice');
    });

    it('defaults the auth selector to the password tab', async () => {
      wrapper = await createWrapper({}, {}, verifiedState);
      await flushPromises();

      const selector = wrapper.find('[data-testid="auth-method-selector"]');
      expect(selector.attributes('data-initial-mode')).toBe('password');
    });

    it('never puts verified in the URL and clears the one-shot flag after showing the banner', async () => {
      wrapper = await createWrapper({}, {}, verifiedState);
      await flushPromises();

      // The banner shows, but the flag never enters the URL...
      expect(wrapper.find('[data-testid="signin-verified-notice"]').exists()).toBe(true);
      expect(router.currentRoute.value.query.verified).toBeUndefined();
      expect(router.currentRoute.value.fullPath).toBe('/signin');
      // ...and it is consumed once: cleared from history state so a refresh
      // (which re-reads window.history.state) would not re-trigger it.
      expect(
        (window.history.state as Record<string, unknown> | null)?.[SIGNIN_VERIFIED_STATE_KEY]
      ).toBeUndefined();
    });

    it('does not show the banner or force a mode without the verified flag', async () => {
      wrapper = await createWrapper({});
      await flushPromises();

      expect(wrapper.find('[data-testid="signin-verified-notice"]').exists()).toBe(false);
      const selector = wrapper.find('[data-testid="auth-method-selector"]');
      // No contextual override — the selector falls back to its own default.
      expect(selector.attributes('data-initial-mode')).toBeUndefined();
    });
  });
});
