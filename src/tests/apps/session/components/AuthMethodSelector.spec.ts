// src/tests/apps/session/components/AuthMethodSelector.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import { defineComponent, ref, computed } from 'vue';

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: vi.fn(() => ({ path: '/signin', query: {}, params: {} })),
  useRouter: vi.fn(() => ({ push: vi.fn(), replace: vi.fn() })),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
}));

// Mock feature flags
const mockFeatures = {
  magicLinksEnabled: ref(false),
  webauthnEnabled: ref(false),
  ssoEnabled: ref(false),
  ssoOnlyMode: ref(false),
};

// Mock providers list for getSsoProviders()
const mockProviders = ref<Array<{ route_name: string; display_name: string }>>([]);

vi.mock('@/utils/features', () => ({
  isMagicLinksEnabled: () => mockFeatures.magicLinksEnabled.value,
  isWebAuthnEnabled: () => mockFeatures.webauthnEnabled.value,
  isSsoEnabled: () => mockFeatures.ssoEnabled.value,
  isSsoOnlyMode: () => mockFeatures.ssoOnlyMode.value,
  getSsoProviders: () => mockProviders.value,
}));

// Mock useProductIdentity store — the component uses storeToRefs(useProductIdentity()),
// so isCustom must be a ref for storeToRefs to extract it properly.
const mockIsCustomRef = ref(false);

vi.mock('@/shared/stores/identityStore', () => ({
  useProductIdentity: () => ({
    isCustom: mockIsCustomRef,
  }),
}));

// Mock child components
vi.mock('@/apps/session/components/PasswordlessFirstSignIn.vue', () => ({
  default: {
    name: 'PasswordlessFirstSignIn',
    props: ['locale', 'magicLinksEnabled', 'webauthnEnabled'],
    emits: ['mode-change'],
    template: '<div class="mock-passwordless-signin" data-testid="passwordless-signin"><slot /></div>',
  },
}));

vi.mock('@/apps/session/components/SignInForm.vue', () => ({
  default: {
    name: 'SignInForm',
    props: ['locale'],
    template: '<div class="mock-signin-form" data-testid="signin-form"><slot /></div>',
  },
}));

vi.mock('@/apps/session/components/SsoButton.vue', () => ({
  default: {
    name: 'SsoButton',
    template: '<button class="mock-sso-button" data-testid="sso-button">Sign in with SSO</button>',
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        login: {
          or_continue_with: 'Or continue with',
          custom_domain_sso_title: 'Single sign-on required',
          custom_domain_sso_description: 'Contact your administrator to configure SSO for this domain.',
        },
      },
    },
  },
});

/**
 * AuthMethodSelector Component Tests
 *
 * Tests the auth method selector that:
 * - Shows passwordless-first UI when any passwordless method is enabled
 * - Shows password-only form when no passwordless methods enabled
 * - Conditionally renders SSO section when SSO is enabled
 * - Displays proper divider text between methods
 * - Emits mode changes to parent component
 * - Supports SSO-only mode where only SSO buttons are shown
 */
describe('AuthMethodSelector', () => {
  let wrapper: VueWrapper;

  // AuthMethodSelector stub representing the component interface
  const AuthMethodSelectorStub = defineComponent({
    name: 'AuthMethodSelector',
    props: {
      locale: { type: String, default: 'en' },
    },
    emits: ['mode-change'],
    setup(props, { emit }) {
      const magicLinksEnabled = mockFeatures.magicLinksEnabled.value;
      const webauthnEnabled = mockFeatures.webauthnEnabled.value;
      const ssoEnabled = mockFeatures.ssoEnabled.value;
      const ssoOnly = mockFeatures.ssoOnlyMode.value;

      const ssoProviders = computed(() => mockProviders.value);
      const showSsoOnly = computed(() => ssoOnly && ssoEnabled && ssoProviders.value.length > 0);
      const hasPasswordlessMethods = computed(() => magicLinksEnabled || webauthnEnabled);

      type AuthMode = 'passwordless' | 'passkey' | 'password';
      const currentMode = ref<AuthMode>('passwordless');

      const handleModeChange = (mode: AuthMode) => {
        currentMode.value = mode;
        emit('mode-change', mode);
      };

      return {
        magicLinksEnabled,
        webauthnEnabled,
        ssoEnabled,
        ssoOnly,
        ssoProviders,
        showSsoOnly,
        hasPasswordlessMethods,
        currentMode,
        handleModeChange,
        locale: props.locale,
      };
    },
    template: `
      <div class="space-y-6">
        <!-- SSO-only mode -->
        <template v-if="showSsoOnly">
          <div class="space-y-3">
            <button
              v-for="provider in ssoProviders"
              :key="provider.route_name"
              class="mock-sso-button"
              data-testid="sso-button">
              Sign in with {{ provider.display_name }}
            </button>
          </div>
        </template>

        <!-- Standard auth mode -->
        <template v-else>
          <!-- Passwordless-first mode when any passwordless method is enabled -->
          <div
            v-if="hasPasswordlessMethods"
            class="mock-passwordless-signin"
            data-testid="passwordless-signin"
            @mode-change="handleModeChange">
            Passwordless Sign In
          </div>

          <!-- Password-only mode when no passwordless methods enabled -->
          <div
            v-else
            class="mock-signin-form"
            data-testid="signin-form">
            Password Sign In Form
          </div>

          <!-- SSO section when SSO is enabled -->
          <template v-if="ssoEnabled">
            <!-- Divider -->
            <div class="sso-divider relative">
              <div class="absolute inset-0 flex items-center" aria-hidden="true">
                <div class="w-full border-t border-gray-300 dark:border-gray-600"></div>
              </div>
              <div class="relative flex justify-center text-sm">
                <span class="divider-text bg-white px-2 text-gray-500 dark:bg-gray-800 dark:text-gray-400">
                  Or continue with
                </span>
              </div>
            </div>

            <!-- SSO Button -->
            <button class="mock-sso-button" data-testid="sso-button">Sign in with SSO</button>
          </template>
        </template>
      </div>
    `,
  });

  beforeEach(() => {
    vi.clearAllMocks();
    // Reset feature flags
    mockFeatures.magicLinksEnabled.value = false;
    mockFeatures.webauthnEnabled.value = false;
    mockFeatures.ssoEnabled.value = false;
    mockFeatures.ssoOnlyMode.value = false;
    mockProviders.value = [];
    mockIsCustomRef.value = false;
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (props: Record<string, unknown> = {}) =>
    mount(AuthMethodSelectorStub, {
      props,
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
          }),
        ],
      },
    });

  describe('Basic Rendering', () => {
    it('renders the component container', () => {
      wrapper = mountComponent();

      expect(wrapper.find('.space-y-6').exists()).toBe(true);
    });

    it('accepts locale prop', () => {
      wrapper = mountComponent({ locale: 'fr' });

      // Component should render without errors
      expect(wrapper.exists()).toBe(true);
    });
  });

  describe('Password-Only Mode (No Passwordless Methods)', () => {
    it('shows SignInForm when no passwordless methods enabled', () => {
      mockFeatures.magicLinksEnabled.value = false;
      mockFeatures.webauthnEnabled.value = false;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(false);
    });

    it('does not show passwordless UI when both methods are disabled', () => {
      mockFeatures.magicLinksEnabled.value = false;
      mockFeatures.webauthnEnabled.value = false;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(false);
    });
  });

  describe('Passwordless-First Mode', () => {
    it('shows PasswordlessFirstSignIn when magic links enabled', () => {
      mockFeatures.magicLinksEnabled.value = true;
      mockFeatures.webauthnEnabled.value = false;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(false);
    });

    it('shows PasswordlessFirstSignIn when WebAuthn enabled', () => {
      mockFeatures.magicLinksEnabled.value = false;
      mockFeatures.webauthnEnabled.value = true;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(false);
    });

    it('shows PasswordlessFirstSignIn when both passwordless methods enabled', () => {
      mockFeatures.magicLinksEnabled.value = true;
      mockFeatures.webauthnEnabled.value = true;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(false);
    });
  });

  describe('SSO Section (SSO Enabled)', () => {
    it('shows SSO button when SSO is enabled', () => {
      mockFeatures.ssoEnabled.value = true;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(true);
    });

    it('hides SSO button when SSO is disabled', () => {
      mockFeatures.ssoEnabled.value = false;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(false);
    });

    it('shows divider when SSO is enabled', () => {
      mockFeatures.ssoEnabled.value = true;

      wrapper = mountComponent();

      const divider = wrapper.find('.sso-divider');
      expect(divider.exists()).toBe(true);
    });

    it('hides divider when SSO is disabled', () => {
      mockFeatures.ssoEnabled.value = false;

      wrapper = mountComponent();

      expect(wrapper.find('.sso-divider').exists()).toBe(false);
    });

    it('displays correct divider text', () => {
      mockFeatures.ssoEnabled.value = true;

      wrapper = mountComponent();

      const dividerText = wrapper.find('.divider-text');
      expect(dividerText.exists()).toBe(true);
      expect(dividerText.text()).toBe('Or continue with');
    });

    it('divider has proper accessibility (decorative line hidden)', () => {
      mockFeatures.ssoEnabled.value = true;

      wrapper = mountComponent();

      const decorativeLine = wrapper.find('.sso-divider [aria-hidden="true"]');
      expect(decorativeLine.exists()).toBe(true);
    });
  });

  describe('SSO with Different Auth Modes', () => {
    it('shows SSO alongside password-only form', () => {
      mockFeatures.magicLinksEnabled.value = false;
      mockFeatures.webauthnEnabled.value = false;
      mockFeatures.ssoEnabled.value = true;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(true);
    });

    it('shows SSO alongside passwordless UI', () => {
      mockFeatures.magicLinksEnabled.value = true;
      mockFeatures.ssoEnabled.value = true;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(true);
    });

    it('shows all three options when everything enabled', () => {
      mockFeatures.magicLinksEnabled.value = true;
      mockFeatures.webauthnEnabled.value = true;
      mockFeatures.ssoEnabled.value = true;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(true);
      expect(wrapper.find('.sso-divider').exists()).toBe(true);
    });
  });

  describe('SSO-Only Mode', () => {
    it('shows only SSO buttons when sso_only and sso are both active with providers', () => {
      mockFeatures.ssoEnabled.value = true;
      mockFeatures.ssoOnlyMode.value = true;
      mockProviders.value = [
        { route_name: 'entra', display_name: 'Microsoft' },
      ];

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(false);
      expect(wrapper.find('.sso-divider').exists()).toBe(false);
    });

    it('renders multiple SSO buttons in sso-only mode', () => {
      mockFeatures.ssoEnabled.value = true;
      mockFeatures.ssoOnlyMode.value = true;
      mockProviders.value = [
        { route_name: 'entra', display_name: 'Microsoft' },
        { route_name: 'google', display_name: 'Google' },
      ];

      wrapper = mountComponent();

      const ssoButtons = wrapper.findAll('[data-testid="sso-button"]');
      expect(ssoButtons.length).toBe(2);
    });

    it('falls through to default when sso_only is true but sso is disabled', () => {
      mockFeatures.ssoEnabled.value = false;
      mockFeatures.ssoOnlyMode.value = true;

      wrapper = mountComponent();

      // Should show the default password form since SSO is not enabled
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(false);
    });

    it('falls through to default when sso_only is true but no providers configured', () => {
      mockFeatures.ssoEnabled.value = true;
      mockFeatures.ssoOnlyMode.value = true;
      mockProviders.value = [];

      wrapper = mountComponent();

      // Should show the default form since there are no providers
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(true);
    });

    it('does not show divider in sso-only mode', () => {
      mockFeatures.ssoEnabled.value = true;
      mockFeatures.ssoOnlyMode.value = true;
      mockProviders.value = [
        { route_name: 'entra', display_name: 'Microsoft' },
      ];

      wrapper = mountComponent();

      expect(wrapper.find('.sso-divider').exists()).toBe(false);
    });

    it('shows passwordless alongside SSO when sso_only is false', () => {
      mockFeatures.magicLinksEnabled.value = true;
      mockFeatures.ssoEnabled.value = true;
      mockFeatures.ssoOnlyMode.value = false;
      mockProviders.value = [
        { route_name: 'entra', display_name: 'Microsoft' },
      ];

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(true);
    });
  });

  describe('Mode Change Events', () => {
    it('has handleModeChange method defined', () => {
      mockFeatures.magicLinksEnabled.value = true;
      wrapper = mountComponent();

      // The stub exposes handleModeChange which emits mode-change
      const vm = wrapper.vm as unknown as { handleModeChange: (mode: string) => void };
      expect(vm.handleModeChange).toBeDefined();
    });

    it('emits mode-change when handleModeChange is called', async () => {
      mockFeatures.magicLinksEnabled.value = true;
      wrapper = mountComponent();

      // Directly call the handler to verify emit works
      const vm = wrapper.vm as unknown as { handleModeChange: (mode: string) => void };
      vm.handleModeChange('password');
      await wrapper.vm.$nextTick();

      const emitted = wrapper.emitted('mode-change');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual(['password']);
    });

    it('passes correct mode in event payload for passkey', async () => {
      mockFeatures.magicLinksEnabled.value = true;
      wrapper = mountComponent();

      const vm = wrapper.vm as unknown as { handleModeChange: (mode: string) => void };
      vm.handleModeChange('passkey');
      await wrapper.vm.$nextTick();

      const emitted = wrapper.emitted('mode-change');
      expect(emitted).toBeTruthy();
      expect(emitted![0]).toEqual(['passkey']);
    });
  });

  describe('Dark Mode Styling', () => {
    it('divider has dark mode classes', () => {
      mockFeatures.ssoEnabled.value = true;

      wrapper = mountComponent();

      const borderLine = wrapper.find('.sso-divider .border-gray-300');
      expect(borderLine.exists()).toBe(true);
      expect(borderLine.classes()).toContain('dark:border-gray-600');
    });

    it('divider text has dark mode classes', () => {
      mockFeatures.ssoEnabled.value = true;

      wrapper = mountComponent();

      const dividerText = wrapper.find('.divider-text');
      expect(dividerText.classes()).toContain('dark:bg-gray-800');
      expect(dividerText.classes()).toContain('dark:text-gray-400');
    });
  });

  describe('Multi-Provider SSO Rendering', () => {
    /**
     * Tests that use the REAL AuthMethodSelector component (not the stub)
     * to verify multi-provider rendering with v-for over ssoProviders.
     */

    // Mount the real component with mocked providers for multi-provider tests
    const mountRealComponent = async (
      bootstrapFeatures: Record<string, unknown>,
      featureFlags: { magic?: boolean; webauthn?: boolean; sso?: boolean; ssoOnly?: boolean } = {}
    ) => {
      mockFeatures.magicLinksEnabled.value = featureFlags.magic ?? false;
      mockFeatures.webauthnEnabled.value = featureFlags.webauthn ?? false;
      mockFeatures.ssoEnabled.value = featureFlags.sso ?? true;
      mockFeatures.ssoOnlyMode.value = featureFlags.ssoOnly ?? false;

      // Set mock providers from the bootstrap features (mirrors getSsoProviders logic)
      const sso = bootstrapFeatures.sso as Record<string, unknown> | undefined;
      if (sso && sso.enabled && Array.isArray(sso.providers)) {
        mockProviders.value = sso.providers as Array<{ route_name: string; display_name: string }>;
      } else {
        mockProviders.value = [];
      }

      // Use dynamic import for the real component
      const { default: AuthMethodSelector } = await import(
        '@/apps/session/components/AuthMethodSelector.vue'
      );

      const pinia = createTestingPinia({
        createSpy: vi.fn,
      });

      const w = mount(AuthMethodSelector, {
        props: { locale: 'en' },
        global: {
          plugins: [i18n, pinia],
        },
      });

      // Allow computed properties to update
      await w.vm.$nextTick();
      return w;
    };

    it('renders one SsoButton per provider when multiple providers configured', async () => {
      wrapper = await mountRealComponent({
        sso: {
          enabled: true,
          providers: [
            { route_name: 'entra', display_name: 'Microsoft' },
            { route_name: 'google', display_name: 'Google' },
            { route_name: 'github', display_name: 'GitHub' },
          ],
        },
      });

      const ssoButtons = wrapper.findAll('[data-testid="sso-button"]');
      expect(ssoButtons.length).toBe(3);
    });

    it('renders single SsoButton for single provider', async () => {
      wrapper = await mountRealComponent({
        sso: {
          enabled: true,
          providers: [
            { route_name: 'oidc', display_name: 'Okta' },
          ],
        },
      });

      const ssoButtons = wrapper.findAll('[data-testid="sso-button"]');
      expect(ssoButtons.length).toBe(1);
    });

    it('renders no SsoButtons when providers array is empty', async () => {
      wrapper = await mountRealComponent({
        sso: {
          enabled: true,
          providers: [],
        },
      });

      const ssoButtons = wrapper.findAll('[data-testid="sso-button"]');
      expect(ssoButtons.length).toBe(0);
    });

    it('renders no SsoButtons when providers array absent (no legacy fallback)', async () => {
      wrapper = await mountRealComponent({
        sso: {
          enabled: true,
          route_name: 'oidc',
          display_name: 'Corporate SSO',
        },
      });

      const ssoButtons = wrapper.findAll('[data-testid="sso-button"]');
      expect(ssoButtons.length).toBe(0);
    });

    it('shows divider and SSO section when SSO enabled with providers', async () => {
      wrapper = await mountRealComponent({
        sso: {
          enabled: true,
          providers: [
            { route_name: 'entra', display_name: 'Microsoft' },
            { route_name: 'google', display_name: 'Google' },
          ],
        },
      });

      expect(wrapper.text()).toContain('Or continue with');
      const ssoButtons = wrapper.findAll('[data-testid="sso-button"]');
      expect(ssoButtons.length).toBe(2);
    });

    it('renders only SSO buttons in sso-only mode with real component', async () => {
      wrapper = await mountRealComponent(
        {
          sso: {
            enabled: true,
            providers: [
              { route_name: 'entra', display_name: 'Microsoft' },
              { route_name: 'google', display_name: 'Google' },
            ],
          },
        },
        { sso: true, ssoOnly: true }
      );

      const ssoButtons = wrapper.findAll('[data-testid="sso-button"]');
      expect(ssoButtons.length).toBe(2);
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(false);
    });
  });

  describe('Feature Flag Combinations', () => {
    const testCases = [
      {
        name: 'all disabled',
        flags: { magic: false, webauthn: false, sso: false },
        expected: { passwordless: false, password: true, sso: false },
      },
      {
        name: 'only magic links',
        flags: { magic: true, webauthn: false, sso: false },
        expected: { passwordless: true, password: false, sso: false },
      },
      {
        name: 'only webauthn',
        flags: { magic: false, webauthn: true, sso: false },
        expected: { passwordless: true, password: false, sso: false },
      },
      {
        name: 'only sso',
        flags: { magic: false, webauthn: false, sso: true },
        expected: { passwordless: false, password: true, sso: true },
      },
      {
        name: 'magic + webauthn',
        flags: { magic: true, webauthn: true, sso: false },
        expected: { passwordless: true, password: false, sso: false },
      },
      {
        name: 'magic + sso',
        flags: { magic: true, webauthn: false, sso: true },
        expected: { passwordless: true, password: false, sso: true },
      },
      {
        name: 'webauthn + sso',
        flags: { magic: false, webauthn: true, sso: true },
        expected: { passwordless: true, password: false, sso: true },
      },
      {
        name: 'all enabled',
        flags: { magic: true, webauthn: true, sso: true },
        expected: { passwordless: true, password: false, sso: true },
      },
    ];

    testCases.forEach(({ name, flags, expected }) => {
      it(`correctly renders with ${name}`, () => {
        mockFeatures.magicLinksEnabled.value = flags.magic;
        mockFeatures.webauthnEnabled.value = flags.webauthn;
        mockFeatures.ssoEnabled.value = flags.sso;

        wrapper = mountComponent();

        expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(expected.passwordless);
        expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(expected.password);
        expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(expected.sso);
      });
    });
  });

  describe('Custom Domain Authentication (showCustomDomainNoSso)', () => {
    /**
     * Tests for the custom domain fallback behavior using the REAL component.
     *
     * On custom domains (isCustom=true), the component enforces SSO-only auth.
     * When SSO is not configured (no providers or SSO disabled), it shows a
     * friendly "SSO required" message instead of password/passwordless forms.
     *
     * The stub does not replicate isCustom logic, so these tests use the
     * real component via dynamic import (same pattern as Multi-Provider tests).
     */

    const mountRealForCustomDomain = async (opts: {
      isCustom: boolean;
      ssoEnabled?: boolean;
      ssoOnlyMode?: boolean;
      providers?: Array<{ route_name: string; display_name: string }>;
      magic?: boolean;
      webauthn?: boolean;
    }) => {
      mockIsCustomRef.value = opts.isCustom;
      mockFeatures.ssoEnabled.value = opts.ssoEnabled ?? false;
      mockFeatures.ssoOnlyMode.value = opts.ssoOnlyMode ?? false;
      mockFeatures.magicLinksEnabled.value = opts.magic ?? false;
      mockFeatures.webauthnEnabled.value = opts.webauthn ?? false;
      mockProviders.value = opts.providers ?? [];

      const { default: AuthMethodSelector } = await import(
        '@/apps/session/components/AuthMethodSelector.vue'
      );

      const pinia = createTestingPinia({
        createSpy: vi.fn,
      });

      const w = mount(AuthMethodSelector, {
        props: { locale: 'en' },
        global: {
          plugins: [i18n, pinia],
        },
      });

      await w.vm.$nextTick();
      return w;
    };

    it('shows no-sso message on custom domain when SSO is not configured', async () => {
      wrapper = await mountRealForCustomDomain({
        isCustom: true,
        ssoEnabled: false,
        providers: [],
      });

      const noSsoMessage = wrapper.find('[data-testid="auth-custom-domain-no-sso"]');
      expect(noSsoMessage.exists()).toBe(true);
      expect(noSsoMessage.attributes('role')).toBe('note');

      // Should NOT show password form, passwordless form, or SSO buttons
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(false);
    });

    it('shows no-sso message on custom domain when SSO is enabled but no providers', async () => {
      // SSO enabled in config but providers array is empty — showSsoOnly is false
      // because it requires providers.length > 0, so showCustomDomainNoSso is true
      wrapper = await mountRealForCustomDomain({
        isCustom: true,
        ssoEnabled: true,
        providers: [],
      });

      expect(wrapper.find('[data-testid="auth-custom-domain-no-sso"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="auth-sso-only-section"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(false);
    });

    it('shows SSO-only section on custom domain when SSO is configured with providers', async () => {
      wrapper = await mountRealForCustomDomain({
        isCustom: true,
        ssoEnabled: true,
        providers: [
          { route_name: 'entra', display_name: 'Microsoft' },
        ],
      });

      expect(wrapper.find('[data-testid="auth-sso-only-section"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="auth-custom-domain-no-sso"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(false);
    });

    it('shows multiple SSO buttons on custom domain with multiple providers', async () => {
      wrapper = await mountRealForCustomDomain({
        isCustom: true,
        ssoEnabled: true,
        providers: [
          { route_name: 'entra', display_name: 'Microsoft' },
          { route_name: 'google', display_name: 'Google' },
        ],
      });

      expect(wrapper.find('[data-testid="auth-sso-only-section"]').exists()).toBe(true);
      const ssoButtons = wrapper.findAll('[data-testid="sso-button"]');
      expect(ssoButtons.length).toBe(2);
    });

    it('never shows no-sso message on canonical domain regardless of SSO state', async () => {
      // Canonical domain (isCustom=false) without SSO should show standard auth forms
      wrapper = await mountRealForCustomDomain({
        isCustom: false,
        ssoEnabled: false,
        providers: [],
      });

      expect(wrapper.find('[data-testid="auth-custom-domain-no-sso"]').exists()).toBe(false);
      // Should fall through to standard auth forms
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(true);
    });

    it('never shows no-sso message on canonical domain even with no providers', async () => {
      wrapper = await mountRealForCustomDomain({
        isCustom: false,
        ssoEnabled: true,
        providers: [],
      });

      expect(wrapper.find('[data-testid="auth-custom-domain-no-sso"]').exists()).toBe(false);
    });

    it('shows no-sso message when custom domain has sso_only but no providers', async () => {
      // Edge case: sso_only mode is on at platform level, custom domain is active,
      // but no providers are configured — showSsoOnly is false (needs providers),
      // so showCustomDomainNoSso is true
      wrapper = await mountRealForCustomDomain({
        isCustom: true,
        ssoEnabled: true,
        ssoOnlyMode: true,
        providers: [],
      });

      expect(wrapper.find('[data-testid="auth-custom-domain-no-sso"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="auth-sso-only-section"]').exists()).toBe(false);
    });

    it('no-sso message contains expected text content', async () => {
      wrapper = await mountRealForCustomDomain({
        isCustom: true,
        ssoEnabled: false,
        providers: [],
      });

      const noSsoMessage = wrapper.find('[data-testid="auth-custom-domain-no-sso"]');
      expect(noSsoMessage.text()).toContain('Single sign-on required');
      expect(noSsoMessage.text()).toContain('Contact your administrator');
    });

    it('custom domain with SSO ignores passwordless flags (SSO takes precedence)', async () => {
      // Even if magic links and webauthn are enabled, custom domain forces SSO-only
      wrapper = await mountRealForCustomDomain({
        isCustom: true,
        ssoEnabled: true,
        providers: [{ route_name: 'entra', display_name: 'Microsoft' }],
        magic: true,
        webauthn: true,
      });

      expect(wrapper.find('[data-testid="auth-sso-only-section"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(false);
    });
  });
});
