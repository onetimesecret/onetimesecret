// src/tests/components/AppSessionState.spec.ts
//
// #4460 / #4465 / #4461 at the root component: protected content is withheld
// while the session cannot be verified, the stale-session notice is
// persistent, and one session transition produces exactly one message.

import App from '@/App.vue';
import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { SESSION_TRANSITION_KEY } from '@/utils/sessionTransition';
import { createTestingPinia } from '@pinia/testing';
import { mount } from '@vue/test-utils';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, nextTick, reactive } from 'vue';

const route = reactive<{ meta: Record<string, unknown>; name: string; fullPath: string }>({
  meta: {},
  name: 'Test',
  fullPath: '/test',
});

vi.mock('vue-router', async (importOriginal) => ({
  ...(await importOriginal<typeof import('vue-router')>()),
  useRoute: () => route,
}));

vi.mock('vue-i18n', async (importOriginal) => ({
  ...(await importOriginal<typeof import('vue-i18n')>()),
  useI18n: () => ({ t: (key: string) => key, locale: { value: 'en' } }),
}));

vi.mock('@/shared/composables/useBrandTheme', () => ({ useBrandTheme: vi.fn() }));
vi.mock('@/shared/components/icons/sprites', () => ({ iconLibraryComponents: {} }));

const ProtectedPage = defineComponent({
  render: () => h('div', { 'data-testid': 'protected-page' }, 'account data'),
});
const Layout = defineComponent({ render() { return h('main', this.$slots.default?.()); } });
const RouterViewStub = defineComponent({
  render() { return this.$slots.default?.({ Component: ProtectedPage }); },
});

function mountApp(status: 'authenticated' | 'unavailable' | 'checking' | 'anonymous', requiresAuth: boolean) {
  route.meta = { requiresAuth, layout: Layout };
  const pinia = createTestingPinia({ createSpy: vi.fn, stubActions: true });
  useBootstrapStore().authStatus = status;
  const wrapper = mount(App, {
    global: {
      plugins: [pinia],
      mocks: { $route: route },
      stubs: {
        // Stands in for the router: hands the slot the matched component.
        RouterView: RouterViewStub,
        RouteErrorBoundary: defineComponent({ render() { return this.$slots.default?.(); } }),
        ImpersonationBanner: true,
        NotificationHost: true,
        CriticalSprites: true,
        OIcon: true,
      },
    },
  });
  return { wrapper, authStore: useAuthStore() };
}

describe('App: session state at the root', () => {
  beforeEach(() => sessionStorage.clear());

  describe('protected content while verification is unavailable (#4460)', () => {
    it('renders the protected page when authenticated', () => {
      const { wrapper } = mountApp('authenticated', true);

      expect(wrapper.find('[data-testid="protected-page"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="verification-unavailable"]').exists()).toBe(false);
    });

    it.each(['unavailable', 'checking'] as const)(
      'withholds it in `%s` and offers retry instead',
      (status) => {
        const { wrapper } = mountApp(status, true);

        expect(wrapper.find('[data-testid="protected-page"]').exists()).toBe(false);
        expect(wrapper.text()).not.toContain('account data');
        expect(wrapper.find('[data-testid="verification-retry"]').exists()).toBe(true);
      }
    );

    it('does not withhold a public route', () => {
      const { wrapper } = mountApp('unavailable', false);

      expect(wrapper.find('[data-testid="protected-page"]').exists()).toBe(true);
    });

    it('recovers in place when verification succeeds: no page load involved', async () => {
      const { wrapper } = mountApp('unavailable', true);

      useBootstrapStore().authStatus = 'authenticated';
      await nextTick();

      expect(wrapper.find('[data-testid="protected-page"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="verification-unavailable"]').exists()).toBe(false);
    });

    it('retry goes through the coordinator', async () => {
      const { wrapper, authStore } = mountApp('unavailable', true);
      vi.mocked(authStore.retryNow).mockResolvedValue('failed');

      await wrapper.find('[data-testid="verification-retry"]').trigger('click');
      await nextTick();
      await nextTick();

      expect(authStore.retryNow).toHaveBeenCalledTimes(1);
      expect(wrapper.find('[data-testid="verification-retry-failed"]').exists()).toBe(true);
    });
  });

  describe('stale-session notice (#4465)', () => {
    it('is absent in the ordinary case', () => {
      const { wrapper } = mountApp('authenticated', true);

      expect(wrapper.find('[data-testid="stale-session-notice"]').exists()).toBe(false);
    });

    it('is persistent once the state is entered, and leaves the page content in place', async () => {
      const { wrapper, authStore } = mountApp('authenticated', true);

      authStore.staleSession = true;
      await nextTick();

      const notice = wrapper.find('[data-testid="stale-session-notice"]');
      expect(notice.attributes('role')).toBe('alert');
      expect(wrapper.find('[data-testid="stale-session-reload"]').exists()).toBe(true);
      // The user must still be able to copy unsubmitted input.
      expect(wrapper.find('[data-testid="protected-page"]').exists()).toBe(true);
      // Nothing dismisses it: no close control, no timer.
      expect(notice.findAll('button')).toHaveLength(1);
    });
  });

  describe('one transition, one message (#4461)', () => {
    it.each(['ended', 'replaced'] as const)('announces a parked `%s` once and removes it', (kind) => {
      sessionStorage.setItem(SESSION_TRANSITION_KEY, kind);

      mountApp('anonymous', false);
      const notifications = useNotificationsStore();

      expect(notifications.show).toHaveBeenCalledTimes(1);
      expect(notifications.show).toHaveBeenCalledWith(`web.auth.session.${kind}`, 'info', 'top', 10000);
      expect(sessionStorage.getItem(SESSION_TRANSITION_KEY)).toBeNull();
    });

    it('a second mount says nothing', () => {
      sessionStorage.setItem(SESSION_TRANSITION_KEY, 'ended');
      mountApp('anonymous', false);

      mountApp('anonymous', false);

      expect(useNotificationsStore().show).not.toHaveBeenCalled();
    });

    it('says nothing on an ordinary page load', () => {
      mountApp('authenticated', true);

      expect(useNotificationsStore().show).not.toHaveBeenCalled();
    });
  });
});
