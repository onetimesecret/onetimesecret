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
 */

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import { createRouter, createMemoryHistory, Router } from 'vue-router';
import { nextTick, defineComponent } from 'vue';
import Login from '@/apps/session/views/Login.vue';

// Mock child components to isolate Login view testing
vi.mock('@/apps/session/components/AuthMethodSelector.vue', () => ({
  default: defineComponent({
    name: 'AuthMethodSelector',
    template: '<div data-testid="auth-method-selector">AuthMethodSelector</div>',
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

// Mock stores
vi.mock('@/shared/stores/languageStore', () => ({
  useLanguageStore: () => ({
    currentLocale: 'en',
  }),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        login: {
          title: 'Sign in',
          subtitle: 'Welcome back',
          errors: {
            sso_failed: 'SSO authentication failed. Please try again.',
            token_missing: 'Login link is missing required token.',
            token_expired: 'Login link has expired. Please request a new one.',
            token_invalid: 'Login link is invalid. Please request a new one.',
          },
          create_account_prefix: "Don't have an account?",
          create_account_link: 'Sign up',
        },
      },
    },
  },
});

describe('Login.vue auth_error handling', () => {
  let router: Router;
  let wrapper: VueWrapper;

  const createWrapper = async (query: Record<string, string> = {}) => {
    router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/signin', name: 'signin', component: Login },
        { path: '/signup', name: 'signup', component: { template: '<div />' } },
      ],
    });

    await router.push({ path: '/signin', query });
    await router.isReady();

    return mount(Login, {
      global: {
        plugins: [
          router,
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
            stubActions: false,
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
  });

  describe('error code handling', () => {
    it('displays SSO error when auth_error=sso_failed', async () => {
      wrapper = await createWrapper({ auth_error: 'sso_failed' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('SSO authentication failed');
    });

    it('displays token expired error', async () => {
      wrapper = await createWrapper({ auth_error: 'token_expired' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('expired');
    });

    it('displays token missing error', async () => {
      wrapper = await createWrapper({ auth_error: 'token_missing' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('missing');
    });

    it('displays token invalid error', async () => {
      wrapper = await createWrapper({ auth_error: 'token_invalid' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(true);
      expect(alert.text()).toContain('invalid');
    });

    it('ignores unknown error codes', async () => {
      wrapper = await createWrapper({ auth_error: 'unknown_error_code' });
      await flushPromises();

      const alert = wrapper.find('[role="alert"]');
      expect(alert.exists()).toBe(false);
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
});
