// src/tests/apps/session/views/LinkSso.spec.ts

import { mount, flushPromises, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { defineComponent, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import type { LinkSsoChallenge } from '@/schemas/api/auth/responses/auth';
import type { LinkSsoErrorCode } from '@/shared/composables/useLinkSso';

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
  challenge: ref<LinkSsoChallenge | null>(null),
  isLoading: ref(false),
  error: ref<string | null>(null),
  errorCode: ref<LinkSsoErrorCode>(null),
  fetchChallenge: vi.fn(),
  verifyLink: vi.fn(),
  clearError: vi.fn(),
};
vi.mock('@/shared/composables/useLinkSso', () => ({
  useLinkSso: () => mockState,
}));

import LinkSso from '@/apps/session/views/LinkSso.vue';

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
        link_sso: {
          prompt: 'You signed in with {provider}, matching {email}.',
        },
      },
    },
  },
});

const makeChallenge = (overrides: Partial<LinkSsoChallenge> = {}): LinkSsoChallenge => ({
  provider: 'entra',
  email: 'user@example.com',
  ...overrides,
});

/**
 * LinkSso Component Tests (#3840 Phase 3 — sign-in interstitial)
 *
 * Verifies the password-proof interstitial an unauthenticated SSO sign-in is
 * redirected to when its IdP email matches an existing password account:
 * - fetches the challenge context on mount and names provider + claimed email
 * - collects the EXISTING password and completes sign-in on success
 * - keeps the user on the form for a wrong password (retry)
 * - dead-ends (settings pointer) for a missing / expired / spent token
 * - cancel routes to /signin carrying the Connected Identities destination
 */
describe('LinkSso', () => {
  let wrapper: VueWrapper;

  const mountComponent = () => mount(LinkSso, { global: { plugins: [i18n] } });

  beforeEach(() => {
    vi.clearAllMocks();
    mockRoute.params = { token: 'challenge-token-123' };
    mockRoute.query = {};
    mockState.challenge.value = null;
    mockState.isLoading.value = false;
    mockState.error.value = null;
    mockState.errorCode.value = null;
    mockState.fetchChallenge.mockResolvedValue(makeChallenge());
    mockState.verifyLink.mockResolvedValue({ success: 'ok' });
    mockAuthStore.isFullyAuthenticated = false;
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  describe('Mount / challenge fetch', () => {
    it('fetches the challenge with the token from the route path param', async () => {
      wrapper = mountComponent();
      await flushPromises();
      expect(mockState.fetchChallenge).toHaveBeenCalledWith('challenge-token-123');
    });

    it('redirects a fully authenticated user home and does not fetch', async () => {
      mockAuthStore.isFullyAuthenticated = true;
      wrapper = mountComponent();
      await flushPromises();
      expect(mockPush).toHaveBeenCalledWith('/');
      expect(mockState.fetchChallenge).not.toHaveBeenCalled();
    });

    it('dead-ends without fetching when the token is missing', async () => {
      mockRoute.params = {};
      wrapper = mountComponent();
      await flushPromises();
      expect(mockState.fetchChallenge).not.toHaveBeenCalled();
      expect(wrapper.find('[data-testid="link-sso-unavailable"]').exists()).toBe(true);
    });

    it('dead-ends when the challenge fetch fails (expired / spent token)', async () => {
      mockState.fetchChallenge.mockResolvedValue(null);
      wrapper = mountComponent();
      await flushPromises();
      expect(wrapper.find('[data-testid="link-sso-unavailable"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="link-sso-password-input"]').exists()).toBe(false);
    });
  });

  describe('Challenge display', () => {
    beforeEach(() => {
      mockState.challenge.value = makeChallenge();
    });

    it('names the provider (friendly label) and the claimed email', async () => {
      wrapper = mountComponent();
      await flushPromises();
      const prompt = wrapper.find('[data-testid="link-sso-prompt"]');
      expect(prompt.exists()).toBe(true);
      // i18n is pass-through; interpolated params are substituted into the key text.
      expect(prompt.text()).toContain('Microsoft Entra');
      expect(prompt.text()).toContain('user@example.com');
    });

    it('renders the password form', async () => {
      wrapper = mountComponent();
      await flushPromises();
      expect(wrapper.find('[data-testid="link-sso-password-input"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="link-sso-submit"]').exists()).toBe(true);
    });

    it('falls back to a capitalized provider name for unknown providers', async () => {
      mockState.challenge.value = makeChallenge({ provider: 'okta' });
      wrapper = mountComponent();
      await flushPromises();
      expect(wrapper.find('[data-testid="link-sso-prompt"]').text()).toContain('Okta');
    });
  });

  describe('Verify success', () => {
    beforeEach(() => {
      mockState.challenge.value = makeChallenge();
    });

    it('completes sign-in and navigates to the dashboard by default', async () => {
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="link-sso-password-input"]').setValue('correct horse');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockState.verifyLink).toHaveBeenCalledWith('challenge-token-123', 'correct horse');
      expect(mockSetAuthenticated).toHaveBeenCalledWith(true);
      expect(mockPush).toHaveBeenCalledWith('/');
    });

    it('prefers the redirect target returned by the backend when it is internal', async () => {
      mockState.verifyLink.mockResolvedValue({ success: 'ok', redirect: '/dashboard' });
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="link-sso-password-input"]').setValue('pw');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockPush).toHaveBeenCalledWith('/dashboard');
    });

    it('falls back to the ?redirect query param when the response carries none', async () => {
      mockRoute.query = { redirect: '/account/settings' };
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="link-sso-password-input"]').setValue('pw');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockPush).toHaveBeenCalledWith('/account/settings');
    });

    it('ignores an external redirect target from the backend', async () => {
      mockState.verifyLink.mockResolvedValue({ success: 'ok', redirect: 'https://evil.example/' });
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="link-sso-password-input"]').setValue('pw');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockPush).toHaveBeenCalledWith('/');
    });

    it('does not submit an empty password', async () => {
      wrapper = mountComponent();
      await flushPromises();
      await wrapper.find('form').trigger('submit');
      await flushPromises();
      expect(mockState.verifyLink).not.toHaveBeenCalled();
    });
  });

  describe('Verify success — MFA required', () => {
    beforeEach(() => {
      mockState.challenge.value = makeChallenge();
    });

    it('does NOT mark fully authenticated and hands off to /mfa-verify', async () => {
      // MFA account: password proven but a second factor is still required.
      mockState.verifyLink.mockResolvedValue({ success: 'ok', mfa_required: true });
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="link-sso-password-input"]').setValue('correct pw');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      // Not fully authenticated — the OTP challenge is not skipped.
      expect(mockSetAuthenticated).not.toHaveBeenCalled();
      // Marked awaiting MFA so the route guard permits /mfa-verify (mirrors Login).
      expect(mockBootstrapUpdate).toHaveBeenCalledWith({
        awaiting_mfa: true,
        authenticated: false,
      });
      expect(mockPush).toHaveBeenCalledWith({ path: '/mfa-verify', query: undefined });
    });

    it('preserves the ?redirect query when handing off to /mfa-verify', async () => {
      mockRoute.query = { redirect: '/account/settings' };
      mockState.verifyLink.mockResolvedValue({ success: 'ok', mfa_required: true });
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="link-sso-password-input"]').setValue('pw');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockPush).toHaveBeenCalledWith({
        path: '/mfa-verify',
        query: { redirect: '/account/settings' },
      });
    });
  });

  describe('Verify failure', () => {
    beforeEach(() => {
      mockState.challenge.value = makeChallenge();
    });

    it('keeps the user on the form and clears the password on a wrong password', async () => {
      mockState.verifyLink.mockImplementation(async () => {
        mockState.errorCode.value = 'invalid_password';
        mockState.error.value = 'web.link_sso.errors.invalid_password';
        return null;
      });
      wrapper = mountComponent();
      await flushPromises();

      const input = wrapper.find<HTMLInputElement>('[data-testid="link-sso-password-input"]');
      await input.setValue('wrong');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      // No navigation, still on the form, error surfaced, password cleared.
      expect(mockSetAuthenticated).not.toHaveBeenCalled();
      expect(mockPush).not.toHaveBeenCalled();
      expect(wrapper.find('[data-testid="link-sso-error"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="link-sso-unavailable"]').exists()).toBe(false);
      expect(input.element.value).toBe('');
    });

    it('dead-ends to the settings pointer when the token expired mid-flow', async () => {
      mockState.verifyLink.mockImplementation(async () => {
        mockState.errorCode.value = 'invalid_token';
        mockState.error.value = 'web.link_sso.errors.invalid_token';
        return null;
      });
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="link-sso-password-input"]').setValue('pw');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(mockSetAuthenticated).not.toHaveBeenCalled();
      expect(wrapper.find('[data-testid="link-sso-unavailable"]').exists()).toBe(true);
    });
  });

  describe('Cancel / dead-end navigation', () => {
    it('cancel routes to /signin carrying the connections destination + pointer', async () => {
      mockState.challenge.value = makeChallenge();
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="link-sso-cancel"]').trigger('click');

      expect(mockPush).toHaveBeenCalledWith({
        path: '/signin',
        query: {
          auth_error: 'link_sso_failed',
          redirect: '/account/settings/security/connections',
        },
      });
    });

    it('the dead-end panel action routes to /signin with the same pointer', async () => {
      mockState.fetchChallenge.mockResolvedValue(null);
      wrapper = mountComponent();
      await flushPromises();

      await wrapper.find('[data-testid="link-sso-unavailable-action"]').trigger('click');

      expect(mockPush).toHaveBeenCalledWith({
        path: '/signin',
        query: {
          auth_error: 'link_sso_failed',
          redirect: '/account/settings/security/connections',
        },
      });
    });
  });

  describe('Accessibility', () => {
    // Focus assertions need a real document connection.
    const mountAttached = () =>
      mount(LinkSso, { global: { plugins: [i18n] }, attachTo: document.body });

    it('moves focus to the dead-end panel heading when the token expires mid-flow', async () => {
      mockState.challenge.value = makeChallenge();
      mockState.verifyLink.mockImplementation(async () => {
        mockState.errorCode.value = 'invalid_token';
        mockState.error.value = 'web.link_sso.errors.invalid_token';
        return null;
      });
      wrapper = mountAttached();
      await flushPromises();

      await wrapper.find('[data-testid="link-sso-password-input"]').setValue('pw');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      // The form that held focus is unmounted; without this, focus falls to
      // <body> and the refusal is never announced.
      const heading = wrapper.find('#link-sso-unavailable-title');
      expect(heading.exists()).toBe(true);
      expect(document.activeElement).toBe(heading.element);
    });

    it('keeps a single live region mounted so status changes are announced', async () => {
      mockState.challenge.value = makeChallenge();
      wrapper = mountComponent();
      await flushPromises();

      // Present (and empty) BEFORE the status changes — a region inserted with
      // its text already in place is not reliably announced.
      const region = wrapper.find('[data-testid="link-sso-status"]');
      expect(region.exists()).toBe(true);
      expect(region.attributes('aria-live')).toBe('polite');
      expect(region.text()).toBe('');

      mockState.isLoading.value = true;
      await wrapper.vm.$nextTick();

      expect(wrapper.find('[data-testid="link-sso-status"]').text()).toBe(
        'web.COMMON.form_processing'
      );
    });

    it('gives every action a pointer cursor (Tailwind v4 drops the button default)', async () => {
      mockState.challenge.value = makeChallenge();
      wrapper = mountComponent();
      await flushPromises();

      for (const testid of ['link-sso-submit', 'link-sso-cancel']) {
        expect(wrapper.find(`[data-testid="${testid}"]`).classes()).toContain('cursor-pointer');
      }

      wrapper.unmount();
      mockState.challenge.value = null;
      mockState.fetchChallenge.mockResolvedValue(null);
      wrapper = mountComponent();
      await flushPromises();

      expect(wrapper.find('[data-testid="link-sso-unavailable-action"]').classes()).toContain(
        'cursor-pointer'
      );
    });
  });
});
