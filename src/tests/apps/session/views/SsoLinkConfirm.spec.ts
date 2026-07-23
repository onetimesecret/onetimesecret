// src/tests/apps/session/views/SsoLinkConfirm.spec.ts

import { mount, flushPromises, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { defineComponent, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import type { SsoLinkConfirmDisplay } from '@/schemas/api/auth/responses/auth';
import type { SsoLinkConfirmErrorCode } from '@/shared/composables/useSsoLinkConfirm';

// Router: controllable route (params.token, query.redirect) + spyable push.
const mockPush = vi.fn();
const mockRoute: { params: Record<string, unknown>; query: Record<string, unknown> } = {
  params: {},
  query: {},
};
vi.mock('vue-router', () => ({
  useRoute: () => mockRoute,
  useRouter: () => ({ push: mockPush }),
}));

// AuthView: render named slots inline so slot content is testable.
vi.mock('@/apps/session/components/AuthView.vue', () => ({
  default: defineComponent({
    name: 'AuthView',
    template: `<div data-testid="auth-view"><slot name="form" /><slot name="footer" /></div>`,
    props: ['heading', 'headingId', 'withSubheading', 'showReturnHome', 'title', 'titleLogo'],
  }),
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Auth store: controllable auth state + spyable setAuthenticated.
const mockSetAuthenticated = vi.fn();
const mockAuthStore = { isFullyAuthenticated: false, setAuthenticated: mockSetAuthenticated };
vi.mock('@/shared/stores/authStore', () => ({
  useAuthStore: () => mockAuthStore,
}));

// Bootstrap store: MFA hand-off marks awaiting_mfa via update() (mirrors Login).
const mockBootstrapUpdate = vi.fn();
vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => ({ update: mockBootstrapUpdate }),
}));

// Composable: controllable reactive state + spies.
const mockState = {
  pendingLink: ref<SsoLinkConfirmDisplay | null>(null),
  isLoading: ref(false),
  error: ref<string | null>(null),
  errorCode: ref<SsoLinkConfirmErrorCode>(null),
  fetchPendingLink: vi.fn(),
  confirmLink: vi.fn(),
  clearError: vi.fn(),
};
vi.mock('@/shared/composables/useSsoLinkConfirm', () => ({
  useSsoLinkConfirm: () => mockState,
}));

import SsoLinkConfirm from '@/apps/session/views/SsoLinkConfirm.vue';

// Pass-through i18n (keys render as-is), EXCEPT the prompt is given a real
// interpolating message so the provider label + claimed email are observable in
// the rendered text (the pass-through `missing` handler drops interpolation).
const i18n = createI18n({
  legacy: false,
  locale: 'en',
  missingWarn: false,
  fallbackWarn: false,
  missing: (_: unknown, key: string) => key,
  messages: {
    en: {
      web: {
        sso_link_confirm: {
          prompt: 'You signed in with {provider}, matching {email}.',
        },
      },
    },
  },
});

const makeLink = (overrides: Partial<SsoLinkConfirmDisplay> = {}): SsoLinkConfirmDisplay => ({
  provider: 'entra',
  email: 'user@example.com',
  ...overrides,
});

/**
 * SsoLinkConfirm Component Tests (#3840 Phase 4 — mailbox-proof linking)
 *
 * Verifies the consent page an emailed link opens for a PASSWORDLESS account:
 * - fetches the display context on mount and names provider + claimed email
 * - confirms via a single CTA (NO password — mailbox possession is the proof)
 *   and completes sign-in on success
 * - hands an MFA account off to /mfa-verify without completing sign-in
 * - dead-ends (terminal panel) for a missing / expired / spent token OR any
 *   confirm failure (conflict / invalidated) — a single-use token has no retry
 * - cancel / dead-end action route to /signin (passwordless: re-do SSO)
 */
describe('SsoLinkConfirm', () => {
  let wrapper: VueWrapper;

  const mountComponent = () => mount(SsoLinkConfirm, { global: { plugins: [i18n] } });

  beforeEach(() => {
    vi.clearAllMocks();
    mockRoute.params = { token: 'confirm-token-123' };
    mockRoute.query = {};
    mockState.pendingLink.value = null;
    mockState.isLoading.value = false;
    mockState.error.value = null;
    mockState.errorCode.value = null;
    mockState.fetchPendingLink.mockResolvedValue(makeLink());
    mockState.confirmLink.mockResolvedValue({ success: 'ok' });
    mockAuthStore.isFullyAuthenticated = false;
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  describe('Mount / display fetch', () => {
    it('fetches the display context with the token from the route path param', async () => {
      wrapper = mountComponent();
      await flushPromises();
      expect(mockState.fetchPendingLink).toHaveBeenCalledWith('confirm-token-123');
    });

    it('does NOT confirm (POST) on load — only on explicit consent', async () => {
      wrapper = mountComponent();
      await flushPromises();
      // Never auto-POST: a mail/link prefetch of the page must not burn the token.
      expect(mockState.confirmLink).not.toHaveBeenCalled();
    });

    it('redirects a fully authenticated user home and does not fetch', async () => {
      mockAuthStore.isFullyAuthenticated = true;
      wrapper = mountComponent();
      await flushPromises();
      expect(mockPush).toHaveBeenCalledWith('/');
      expect(mockState.fetchPendingLink).not.toHaveBeenCalled();
    });

    it('dead-ends without fetching when the token is missing', async () => {
      mockRoute.params = {};
      wrapper = mountComponent();
      await flushPromises();
      expect(mockState.fetchPendingLink).not.toHaveBeenCalled();
      expect(wrapper.find('[data-testid="sso-link-confirm-unavailable"]').exists()).toBe(true);
    });

    it('dead-ends when the display fetch fails (expired / spent token)', async () => {
      mockState.fetchPendingLink.mockResolvedValue(null);
      wrapper = mountComponent();
      await flushPromises();
      expect(wrapper.find('[data-testid="sso-link-confirm-unavailable"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="sso-link-confirm-submit"]').exists()).toBe(false);
    });
  });

  describe('Consent display', () => {
    beforeEach(() => {
      mockState.pendingLink.value = makeLink();
    });

    it('names the provider (friendly label) and the claimed email', async () => {
      wrapper = mountComponent();
      await flushPromises();
      const prompt = wrapper.find('[data-testid="sso-link-confirm-prompt"]');
      expect(prompt.exists()).toBe(true);
      expect(prompt.text()).toContain('Microsoft Entra');
      expect(prompt.text()).toContain('user@example.com');
    });

    it('renders the confirm CTA and NO password field', async () => {
      wrapper = mountComponent();
      await flushPromises();
      expect(wrapper.find('[data-testid="sso-link-confirm-submit"]').exists()).toBe(true);
      expect(wrapper.find('input[type="password"]').exists()).toBe(false);
    });

    it('falls back to a capitalized provider name for unknown providers', async () => {
      mockState.pendingLink.value = makeLink({ provider: 'okta' });
      wrapper = mountComponent();
      await flushPromises();
      expect(wrapper.find('[data-testid="sso-link-confirm-prompt"]').text()).toContain('Okta');
    });
  });

  describe('Confirm success', () => {
    beforeEach(() => {
      mockState.pendingLink.value = makeLink();
    });

    it('confirms with the token, completes sign-in, and navigates home by default', async () => {
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="sso-link-confirm-submit"]').trigger('click');
      await flushPromises();

      expect(mockState.confirmLink).toHaveBeenCalledWith('confirm-token-123');
      expect(mockSetAuthenticated).toHaveBeenCalledWith(true);
      expect(mockPush).toHaveBeenCalledWith('/');
    });

    it('prefers the redirect target returned by the backend when it is internal', async () => {
      mockState.confirmLink.mockResolvedValue({ success: 'ok', redirect: '/dashboard' });
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="sso-link-confirm-submit"]').trigger('click');
      await flushPromises();

      expect(mockPush).toHaveBeenCalledWith('/dashboard');
    });

    it('falls back to the ?redirect query param when the response carries none', async () => {
      mockRoute.query = { redirect: '/account/settings' };
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="sso-link-confirm-submit"]').trigger('click');
      await flushPromises();

      expect(mockPush).toHaveBeenCalledWith('/account/settings');
    });

    it('ignores an external redirect target from the backend', async () => {
      mockState.confirmLink.mockResolvedValue({ success: 'ok', redirect: 'https://evil.example/' });
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="sso-link-confirm-submit"]').trigger('click');
      await flushPromises();

      expect(mockPush).toHaveBeenCalledWith('/');
    });
  });

  describe('Confirm success — MFA required', () => {
    beforeEach(() => {
      mockState.pendingLink.value = makeLink();
    });

    it('does NOT mark fully authenticated and hands off to /mfa-verify', async () => {
      mockState.confirmLink.mockResolvedValue({ success: 'ok', mfa_required: true });
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="sso-link-confirm-submit"]').trigger('click');
      await flushPromises();

      expect(mockSetAuthenticated).not.toHaveBeenCalled();
      expect(mockBootstrapUpdate).toHaveBeenCalledWith({
        awaiting_mfa: true,
        authenticated: false,
      });
      expect(mockPush).toHaveBeenCalledWith({ path: '/mfa-verify', query: undefined });
    });

    it('preserves the ?redirect query when handing off to /mfa-verify', async () => {
      mockRoute.query = { redirect: '/account/settings' };
      mockState.confirmLink.mockResolvedValue({ success: 'ok', mfa_required: true });
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="sso-link-confirm-submit"]').trigger('click');
      await flushPromises();

      expect(mockPush).toHaveBeenCalledWith({
        path: '/mfa-verify',
        query: { redirect: '/account/settings' },
      });
    });
  });

  describe('Confirm failure', () => {
    beforeEach(() => {
      mockState.pendingLink.value = makeLink();
    });

    it('flips to the terminal panel (no retry) and does not authenticate on a conflict', async () => {
      mockState.confirmLink.mockImplementation(async () => {
        mockState.errorCode.value = 'link_conflict';
        mockState.error.value = 'web.sso_link_confirm.errors.link_conflict';
        return null;
      });
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="sso-link-confirm-submit"]').trigger('click');
      await flushPromises();

      expect(mockSetAuthenticated).not.toHaveBeenCalled();
      expect(mockPush).not.toHaveBeenCalled();
      expect(wrapper.find('[data-testid="sso-link-confirm-unavailable"]').exists()).toBe(true);
      // The consent CTA is gone — a single-use token has no retry path.
      expect(wrapper.find('[data-testid="sso-link-confirm-submit"]').exists()).toBe(false);
    });

    it('shows the classified reason in the terminal panel body', async () => {
      mockState.confirmLink.mockImplementation(async () => {
        mockState.errorCode.value = 'link_invalidated';
        mockState.error.value = 'web.sso_link_confirm.errors.link_invalidated';
        return null;
      });
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="sso-link-confirm-submit"]').trigger('click');
      await flushPromises();

      expect(wrapper.find('[data-testid="sso-link-confirm-unavailable"]').text()).toContain(
        'web.sso_link_confirm.errors.link_invalidated'
      );
    });
  });

  describe('Cancel / dead-end navigation', () => {
    it('cancel routes to /signin (passwordless: re-do SSO)', async () => {
      mockState.pendingLink.value = makeLink();
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="sso-link-confirm-cancel"]').trigger('click');

      expect(mockPush).toHaveBeenCalledWith('/signin');
    });

    it('the dead-end panel action routes to /signin', async () => {
      mockState.fetchPendingLink.mockResolvedValue(null);
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="sso-link-confirm-unavailable-action"]').trigger('click');

      expect(mockPush).toHaveBeenCalledWith('/signin');
    });
  });
});
