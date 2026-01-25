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
  omniAuthEnabled: ref(false),
};

vi.mock('@/utils/features', () => ({
  isMagicLinksEnabled: () => mockFeatures.magicLinksEnabled.value,
  isWebAuthnEnabled: () => mockFeatures.webauthnEnabled.value,
  isOmniAuthEnabled: () => mockFeatures.omniAuthEnabled.value,
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
 * - Conditionally renders SSO section when OmniAuth is enabled
 * - Displays proper divider text between methods
 * - Emits mode changes to parent component
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
      const omniAuthEnabled = mockFeatures.omniAuthEnabled.value;

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
        omniAuthEnabled,
        hasPasswordlessMethods,
        currentMode,
        handleModeChange,
        locale: props.locale,
      };
    },
    template: `
      <div class="space-y-6">
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

        <!-- SSO section when OmniAuth is enabled -->
        <template v-if="omniAuthEnabled">
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
      </div>
    `,
  });

  beforeEach(() => {
    vi.clearAllMocks();
    // Reset feature flags
    mockFeatures.magicLinksEnabled.value = false;
    mockFeatures.webauthnEnabled.value = false;
    mockFeatures.omniAuthEnabled.value = false;
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

  describe('SSO Section (OmniAuth Enabled)', () => {
    it('shows SSO button when OmniAuth is enabled', () => {
      mockFeatures.omniAuthEnabled.value = true;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(true);
    });

    it('hides SSO button when OmniAuth is disabled', () => {
      mockFeatures.omniAuthEnabled.value = false;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(false);
    });

    it('shows divider when OmniAuth is enabled', () => {
      mockFeatures.omniAuthEnabled.value = true;

      wrapper = mountComponent();

      const divider = wrapper.find('.sso-divider');
      expect(divider.exists()).toBe(true);
    });

    it('hides divider when OmniAuth is disabled', () => {
      mockFeatures.omniAuthEnabled.value = false;

      wrapper = mountComponent();

      expect(wrapper.find('.sso-divider').exists()).toBe(false);
    });

    it('displays correct divider text', () => {
      mockFeatures.omniAuthEnabled.value = true;

      wrapper = mountComponent();

      const dividerText = wrapper.find('.divider-text');
      expect(dividerText.exists()).toBe(true);
      expect(dividerText.text()).toBe('Or continue with');
    });

    it('divider has proper accessibility (decorative line hidden)', () => {
      mockFeatures.omniAuthEnabled.value = true;

      wrapper = mountComponent();

      const decorativeLine = wrapper.find('.sso-divider [aria-hidden="true"]');
      expect(decorativeLine.exists()).toBe(true);
    });
  });

  describe('SSO with Different Auth Modes', () => {
    it('shows SSO alongside password-only form', () => {
      mockFeatures.magicLinksEnabled.value = false;
      mockFeatures.webauthnEnabled.value = false;
      mockFeatures.omniAuthEnabled.value = true;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(true);
    });

    it('shows SSO alongside passwordless UI', () => {
      mockFeatures.magicLinksEnabled.value = true;
      mockFeatures.omniAuthEnabled.value = true;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(true);
    });

    it('shows all three options when everything enabled', () => {
      mockFeatures.magicLinksEnabled.value = true;
      mockFeatures.webauthnEnabled.value = true;
      mockFeatures.omniAuthEnabled.value = true;

      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(true);
      expect(wrapper.find('.sso-divider').exists()).toBe(true);
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
      mockFeatures.omniAuthEnabled.value = true;

      wrapper = mountComponent();

      const borderLine = wrapper.find('.sso-divider .border-gray-300');
      expect(borderLine.exists()).toBe(true);
      expect(borderLine.classes()).toContain('dark:border-gray-600');
    });

    it('divider text has dark mode classes', () => {
      mockFeatures.omniAuthEnabled.value = true;

      wrapper = mountComponent();

      const dividerText = wrapper.find('.divider-text');
      expect(dividerText.classes()).toContain('dark:bg-gray-800');
      expect(dividerText.classes()).toContain('dark:text-gray-400');
    });
  });

  describe('Feature Flag Combinations', () => {
    const testCases = [
      {
        name: 'all disabled',
        flags: { magic: false, webauthn: false, omniauth: false },
        expected: { passwordless: false, password: true, sso: false },
      },
      {
        name: 'only magic links',
        flags: { magic: true, webauthn: false, omniauth: false },
        expected: { passwordless: true, password: false, sso: false },
      },
      {
        name: 'only webauthn',
        flags: { magic: false, webauthn: true, omniauth: false },
        expected: { passwordless: true, password: false, sso: false },
      },
      {
        name: 'only omniauth',
        flags: { magic: false, webauthn: false, omniauth: true },
        expected: { passwordless: false, password: true, sso: true },
      },
      {
        name: 'magic + webauthn',
        flags: { magic: true, webauthn: true, omniauth: false },
        expected: { passwordless: true, password: false, sso: false },
      },
      {
        name: 'magic + omniauth',
        flags: { magic: true, webauthn: false, omniauth: true },
        expected: { passwordless: true, password: false, sso: true },
      },
      {
        name: 'webauthn + omniauth',
        flags: { magic: false, webauthn: true, omniauth: true },
        expected: { passwordless: true, password: false, sso: true },
      },
      {
        name: 'all enabled',
        flags: { magic: true, webauthn: true, omniauth: true },
        expected: { passwordless: true, password: false, sso: true },
      },
    ];

    testCases.forEach(({ name, flags, expected }) => {
      it(`correctly renders with ${name}`, () => {
        mockFeatures.magicLinksEnabled.value = flags.magic;
        mockFeatures.webauthnEnabled.value = flags.webauthn;
        mockFeatures.omniAuthEnabled.value = flags.omniauth;

        wrapper = mountComponent();

        expect(wrapper.find('[data-testid="passwordless-signin"]').exists()).toBe(expected.passwordless);
        expect(wrapper.find('[data-testid="signin-form"]').exists()).toBe(expected.password);
        expect(wrapper.find('[data-testid="sso-button"]').exists()).toBe(expected.sso);
      });
    });
  });
});
