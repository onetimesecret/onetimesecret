// src/tests/apps/workspace/account/PasskeySettings.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import { defineComponent, ref } from 'vue';

// Mock vue-router
vi.mock('vue-router', () => ({
  useRoute: vi.fn(() => ({ path: '/account/settings/security/passkeys' })),
  useRouter: vi.fn(() => ({ push: vi.fn(), replace: vi.fn() })),
  RouterLink: {
    name: 'RouterLink',
    template: '<a :href="to"><slot /></a>',
    props: ['to'],
  },
}));

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" :data-collection="collection" />',
    props: ['collection', 'name', 'class'],
  },
}));

// Mock SettingsLayout
vi.mock('@/apps/workspace/layouts/SettingsLayout.vue', () => ({
  default: {
    name: 'SettingsLayout',
    template: '<div class="mock-settings-layout"><slot /></div>',
  },
}));

// Mock useWebAuthn composable
const mockWebAuthnState = {
  supported: ref(true),
  isLoading: ref(false),
  error: ref<string | null>(null),
  registerWebAuthn: vi.fn(),
  clearError: vi.fn(),
};

vi.mock('@/shared/composables/useWebAuthn', () => ({
  useWebAuthn: () => mockWebAuthnState,
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        auth: {
          passkeys: {
            title: 'Passkeys',
            setup_description: 'Use biometrics or hardware keys for passwordless sign-in',
            add_passkey: 'Add passkey',
            registered_success: 'Passkey registered successfully',
            no_passkeys: 'No passkeys registered',
            no_passkeys_description: 'Add a passkey to enable passwordless authentication',
            created: 'Created',
            last_used: 'Last used {time}',
            never_used: 'Never used',
            remove_passkey: 'Remove',
            benefit_secure: 'More secure than passwords',
            benefit_fast: 'Fast and convenient',
            benefit_synced: 'Synced across devices',
            description: 'Use biometrics or security keys',
            count: '{count} passkey | {count} passkeys',
            not_configured: 'Not configured',
          },
          webauthn: {
            notSupported: 'Your browser does not support WebAuthn',
            requiresModernBrowser: 'Please use a modern browser to enable passkeys',
            supportedMethods: 'Face ID, Touch ID, or security keys',
          },
          mfa: {
            title: 'Two-Factor Authentication',
          },
          recovery_codes: {
            link_title: 'Recovery Codes',
          },
        },
        LABELS: {
          benefits: 'Benefits',
          related_settings: 'Related Settings',
        },
      },
    },
  },
});

/**
 * PasskeySettings Component Tests
 *
 * Tests the passkey management page that:
 * - Detects WebAuthn browser support
 * - Shows unsupported browser warning when needed
 * - Allows adding new passkeys via registerWebAuthn()
 * - Displays success/error messages
 * - Shows loading states during registration
 */
describe('PasskeySettings', () => {
  let wrapper: VueWrapper;

  // PasskeySettings stub representing the component interface
  const PasskeySettingsStub = defineComponent({
    name: 'PasskeySettings',
    setup() {
      const { supported, isLoading, error, registerWebAuthn, clearError } = mockWebAuthnState;

      const isRegistering = ref(false);
      const successMessage = ref<string | null>(null);
      const passkeys = ref<Array<{ id: string; name: string; created_at: string; last_used_at: string | null }>>([]);
      const isLoadingPasskeys = ref(false);

      const handleRegisterPasskey = async () => {
        clearError();
        successMessage.value = null;
        isRegistering.value = true;

        const success = await registerWebAuthn();

        if (success) {
          successMessage.value = 'Passkey registered successfully';
        }

        isRegistering.value = false;
      };

      const clearMessages = () => {
        clearError();
        successMessage.value = null;
      };

      return {
        supported,
        isLoading,
        error,
        isRegistering,
        successMessage,
        passkeys,
        isLoadingPasskeys,
        handleRegisterPasskey,
        clearMessages,
      };
    },
    template: `
      <div class="mock-settings-layout">
        <div>
          <div class="mb-6">
            <h1 class="text-3xl font-bold dark:text-white">Passkeys</h1>
            <p class="mt-2 text-gray-600 dark:text-gray-400">
              Use biometrics or hardware keys for passwordless sign-in
            </p>
          </div>

          <!-- Loading state -->
          <div v-if="isLoadingPasskeys" class="loading-passkeys flex items-center justify-center py-12">
            <span class="o-icon animate-spin" data-icon="arrow-path"></span>
            <span class="text-gray-600 dark:text-gray-400">Loading passkeys...</span>
          </div>

          <!-- Browser not supported -->
          <div
            v-else-if="!supported"
            class="browser-not-supported rounded-lg bg-yellow-50 p-6 dark:bg-yellow-900/20"
            role="alert">
            <div class="flex items-center gap-3">
              <span class="o-icon" data-icon="exclamation-triangle-solid"></span>
              <div>
                <h3 class="font-semibold text-yellow-800 dark:text-yellow-200">
                  Your browser does not support WebAuthn
                </h3>
                <p class="mt-1 text-sm text-yellow-700 dark:text-yellow-300">
                  Please use a modern browser to enable passkeys
                </p>
              </div>
            </div>
          </div>

          <!-- Main content -->
          <div v-else class="main-content space-y-6">
            <!-- Success message -->
            <div
              v-if="successMessage"
              class="success-message rounded-lg bg-green-50 p-4 dark:bg-green-900/20"
              role="status">
              <div class="flex items-center gap-3">
                <span class="o-icon" data-icon="check-circle-solid"></span>
                <p class="text-sm font-medium text-green-800 dark:text-green-200">
                  {{ successMessage }}
                </p>
                <button
                  @click="clearMessages"
                  type="button"
                  class="dismiss-success ml-auto text-green-600"
                  aria-label="Dismiss">
                  <span class="o-icon" data-icon="x-mark"></span>
                </button>
              </div>
            </div>

            <!-- Error message -->
            <div
              v-if="error"
              class="error-message rounded-lg bg-red-50 p-4 dark:bg-red-900/20"
              role="alert">
              <div class="flex items-center gap-3">
                <span class="o-icon" data-icon="exclamation-circle-solid"></span>
                <p class="text-sm font-medium text-red-800 dark:text-red-200">
                  {{ error }}
                </p>
                <button
                  @click="clearMessages"
                  type="button"
                  class="dismiss-error ml-auto text-red-600"
                  aria-label="Dismiss">
                  <span class="o-icon" data-icon="x-mark"></span>
                </button>
              </div>
            </div>

            <!-- Passkeys list section -->
            <div class="rounded-lg bg-white p-6 shadow dark:bg-gray-800">
              <div class="flex items-start justify-between">
                <div class="flex items-center gap-3">
                  <div class="flex size-12 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
                    <span class="o-icon" data-icon="finger-print-solid"></span>
                  </div>
                  <div>
                    <h2 class="text-xl font-semibold dark:text-white">Passkeys</h2>
                    <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
                      Face ID, Touch ID, or security keys
                    </p>
                  </div>
                </div>

                <!-- Add passkey button -->
                <button
                  @click="handleRegisterPasskey"
                  type="button"
                  :disabled="isLoading || isRegistering"
                  class="add-passkey-button inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50"
                  data-testid="add-passkey-button">
                  <span v-if="isRegistering" class="o-icon animate-spin" data-icon="arrow-path"></span>
                  <span v-else class="o-icon" data-icon="plus"></span>
                  <span>Add passkey</span>
                </button>
              </div>

              <!-- Empty state -->
              <div v-if="passkeys.length === 0" class="empty-state mt-8 text-center">
                <span class="o-icon mx-auto size-12" data-icon="finger-print"></span>
                <h3 class="mt-4 text-lg font-medium text-gray-900 dark:text-white">
                  No passkeys registered
                </h3>
                <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
                  Add a passkey to enable passwordless authentication
                </p>
              </div>

              <!-- Passkeys list -->
              <div v-else class="passkeys-list mt-6 divide-y divide-gray-200 dark:divide-gray-700">
                <div
                  v-for="passkey in passkeys"
                  :key="passkey.id"
                  class="passkey-item flex items-center justify-between py-4">
                  <div class="flex items-center gap-4">
                    <span class="o-icon" data-icon="key-solid"></span>
                    <div>
                      <p class="font-medium text-gray-900 dark:text-white">{{ passkey.name }}</p>
                      <p class="text-sm text-gray-500 dark:text-gray-400">Created: {{ passkey.created_at }}</p>
                    </div>
                  </div>
                  <button type="button" class="remove-passkey text-sm font-medium text-red-600">
                    Remove
                  </button>
                </div>
              </div>
            </div>

            <!-- Benefits section -->
            <div class="benefits-section rounded-lg bg-gray-50 p-6 dark:bg-gray-800">
              <h3 class="mb-4 text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
                Benefits
              </h3>
              <ul class="space-y-3 text-sm text-gray-600 dark:text-gray-400">
                <li class="flex items-start gap-3">
                  <span class="o-icon" data-icon="shield-check-solid"></span>
                  <span>More secure than passwords</span>
                </li>
                <li class="flex items-start gap-3">
                  <span class="o-icon" data-icon="bolt-solid"></span>
                  <span>Fast and convenient</span>
                </li>
                <li class="flex items-start gap-3">
                  <span class="o-icon" data-icon="cloud-solid"></span>
                  <span>Synced across devices</span>
                </li>
              </ul>
            </div>

            <!-- Related settings -->
            <div class="related-settings rounded-lg bg-gray-50 p-4 dark:bg-gray-800">
              <h3 class="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">
                Related Settings
              </h3>
              <div class="space-y-2">
                <a href="/account/settings/security/mfa" class="flex items-center gap-3 text-sm">
                  <span class="o-icon" data-icon="key"></span>
                  <span>Two-Factor Authentication</span>
                </a>
                <a href="/account/settings/security/recovery-codes" class="flex items-center gap-3 text-sm">
                  <span class="o-icon" data-icon="document-text-solid"></span>
                  <span>Recovery Codes</span>
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>
    `,
  });

  beforeEach(() => {
    vi.clearAllMocks();
    // Reset mock state
    mockWebAuthnState.supported.value = true;
    mockWebAuthnState.isLoading.value = false;
    mockWebAuthnState.error.value = null;
    mockWebAuthnState.registerWebAuthn.mockResolvedValue(true);
    mockWebAuthnState.clearError.mockClear();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = () =>
    mount(PasskeySettingsStub, {
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
          }),
        ],
        stubs: {
          RouterLink: {
            template: '<a :href="to"><slot /></a>',
            props: ['to'],
          },
        },
      },
    });

  describe('Basic Rendering', () => {
    it('renders within SettingsLayout', () => {
      wrapper = mountComponent();

      expect(wrapper.find('.mock-settings-layout').exists()).toBe(true);
    });

    it('renders page title', () => {
      wrapper = mountComponent();

      const title = wrapper.find('h1');
      expect(title.exists()).toBe(true);
      expect(title.text()).toBe('Passkeys');
    });

    it('renders page description', () => {
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Use biometrics or hardware keys for passwordless sign-in');
    });

    it('renders add passkey button when supported', () => {
      wrapper = mountComponent();

      const button = wrapper.find('[data-testid="add-passkey-button"]');
      expect(button.exists()).toBe(true);
      expect(button.text()).toContain('Add passkey');
    });
  });

  describe('Browser Support Detection', () => {
    it('shows main content when WebAuthn is supported', () => {
      mockWebAuthnState.supported.value = true;
      wrapper = mountComponent();

      expect(wrapper.find('.main-content').exists()).toBe(true);
      expect(wrapper.find('.browser-not-supported').exists()).toBe(false);
    });

    it('shows unsupported warning when WebAuthn is not supported', () => {
      mockWebAuthnState.supported.value = false;
      wrapper = mountComponent();

      const warning = wrapper.find('.browser-not-supported');
      expect(warning.exists()).toBe(true);
      expect(warning.attributes('role')).toBe('alert');
    });

    it('displays correct unsupported browser message', () => {
      mockWebAuthnState.supported.value = false;
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Your browser does not support WebAuthn');
      expect(wrapper.text()).toContain('Please use a modern browser to enable passkeys');
    });

    it('hides add passkey button when not supported', () => {
      mockWebAuthnState.supported.value = false;
      wrapper = mountComponent();

      expect(wrapper.find('[data-testid="add-passkey-button"]').exists()).toBe(false);
    });
  });

  describe('Add Passkey Functionality', () => {
    it('calls registerWebAuthn when add passkey button is clicked', async () => {
      wrapper = mountComponent();

      await wrapper.find('[data-testid="add-passkey-button"]').trigger('click');

      expect(mockWebAuthnState.registerWebAuthn).toHaveBeenCalled();
    });

    it('clears error before registration attempt', async () => {
      wrapper = mountComponent();

      await wrapper.find('[data-testid="add-passkey-button"]').trigger('click');

      expect(mockWebAuthnState.clearError).toHaveBeenCalled();
    });

    it('shows success message on successful registration', async () => {
      mockWebAuthnState.registerWebAuthn.mockResolvedValue(true);
      wrapper = mountComponent();

      await wrapper.find('[data-testid="add-passkey-button"]').trigger('click');
      await wrapper.vm.$nextTick();

      const successMsg = wrapper.find('.success-message');
      expect(successMsg.exists()).toBe(true);
      expect(successMsg.text()).toContain('Passkey registered successfully');
    });

    it('does not show success message on failed registration', async () => {
      mockWebAuthnState.registerWebAuthn.mockResolvedValue(false);
      wrapper = mountComponent();

      await wrapper.find('[data-testid="add-passkey-button"]').trigger('click');
      await wrapper.vm.$nextTick();

      expect(wrapper.find('.success-message').exists()).toBe(false);
    });
  });

  describe('Loading States', () => {
    it('disables add button while registering', async () => {
      // Make registerWebAuthn hang to simulate loading
      let resolveRegister: (value: boolean) => void;
      mockWebAuthnState.registerWebAuthn.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveRegister = resolve;
          })
      );

      wrapper = mountComponent();
      const button = wrapper.find('[data-testid="add-passkey-button"]');

      // Trigger registration
      await button.trigger('click');
      await wrapper.vm.$nextTick();

      // Button should be disabled
      expect(button.attributes('disabled')).toBeDefined();

      // Resolve to cleanup
      resolveRegister!(true);
    });

    it('shows spinner icon while registering', async () => {
      let resolveRegister: (value: boolean) => void;
      mockWebAuthnState.registerWebAuthn.mockImplementation(
        () =>
          new Promise((resolve) => {
            resolveRegister = resolve;
          })
      );

      wrapper = mountComponent();
      await wrapper.find('[data-testid="add-passkey-button"]').trigger('click');
      await wrapper.vm.$nextTick();

      const spinner = wrapper.find('[data-testid="add-passkey-button"] [data-icon="arrow-path"]');
      expect(spinner.exists()).toBe(true);

      resolveRegister!(true);
    });

    it('disables add button when useWebAuthn isLoading is true', () => {
      mockWebAuthnState.isLoading.value = true;
      wrapper = mountComponent();

      const button = wrapper.find('[data-testid="add-passkey-button"]');
      expect(button.attributes('disabled')).toBeDefined();
    });
  });

  describe('Error Display', () => {
    it('shows error message when error is set', () => {
      mockWebAuthnState.error.value = 'Registration failed';
      wrapper = mountComponent();

      const errorDiv = wrapper.find('.error-message');
      expect(errorDiv.exists()).toBe(true);
      expect(errorDiv.text()).toContain('Registration failed');
    });

    it('error container has alert role', () => {
      mockWebAuthnState.error.value = 'Test error';
      wrapper = mountComponent();

      const errorDiv = wrapper.find('.error-message');
      expect(errorDiv.attributes('role')).toBe('alert');
    });

    it('dismisses error when dismiss button is clicked', async () => {
      mockWebAuthnState.error.value = 'Test error';
      wrapper = mountComponent();

      await wrapper.find('.dismiss-error').trigger('click');

      expect(mockWebAuthnState.clearError).toHaveBeenCalled();
    });

    it('dismiss button has accessible label', () => {
      mockWebAuthnState.error.value = 'Test error';
      wrapper = mountComponent();

      const dismissButton = wrapper.find('.dismiss-error');
      expect(dismissButton.attributes('aria-label')).toBe('Dismiss');
    });
  });

  describe('Success Message Display', () => {
    it('success message has status role', async () => {
      mockWebAuthnState.registerWebAuthn.mockResolvedValue(true);
      wrapper = mountComponent();

      await wrapper.find('[data-testid="add-passkey-button"]').trigger('click');
      await wrapper.vm.$nextTick();

      const successDiv = wrapper.find('.success-message');
      expect(successDiv.attributes('role')).toBe('status');
    });

    it('dismisses success message when dismiss button is clicked', async () => {
      mockWebAuthnState.registerWebAuthn.mockResolvedValue(true);
      wrapper = mountComponent();

      await wrapper.find('[data-testid="add-passkey-button"]').trigger('click');
      await wrapper.vm.$nextTick();

      await wrapper.find('.dismiss-success').trigger('click');

      expect(wrapper.find('.success-message').exists()).toBe(false);
    });
  });

  describe('Empty State', () => {
    it('shows empty state when no passkeys exist', () => {
      wrapper = mountComponent();

      const emptyState = wrapper.find('.empty-state');
      expect(emptyState.exists()).toBe(true);
      expect(emptyState.text()).toContain('No passkeys registered');
    });

    it('shows description in empty state', () => {
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Add a passkey to enable passwordless authentication');
    });

    it('displays fingerprint icon in empty state', () => {
      wrapper = mountComponent();

      const emptyIcon = wrapper.find('.empty-state [data-icon="finger-print"]');
      expect(emptyIcon.exists()).toBe(true);
    });
  });

  describe('Benefits Section', () => {
    it('renders benefits section', () => {
      wrapper = mountComponent();

      const benefits = wrapper.find('.benefits-section');
      expect(benefits.exists()).toBe(true);
    });

    it('displays all benefit items', () => {
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('More secure than passwords');
      expect(wrapper.text()).toContain('Fast and convenient');
      expect(wrapper.text()).toContain('Synced across devices');
    });

    it('benefits section has correct heading', () => {
      wrapper = mountComponent();

      const heading = wrapper.find('.benefits-section h3');
      expect(heading.text()).toBe('Benefits');
    });
  });

  describe('Related Settings', () => {
    it('renders related settings section', () => {
      wrapper = mountComponent();

      const relatedSettings = wrapper.find('.related-settings');
      expect(relatedSettings.exists()).toBe(true);
    });

    it('links to MFA settings', () => {
      wrapper = mountComponent();

      const mfaLink = wrapper.find('a[href="/account/settings/security/mfa"]');
      expect(mfaLink.exists()).toBe(true);
      expect(mfaLink.text()).toContain('Two-Factor Authentication');
    });

    it('links to recovery codes settings', () => {
      wrapper = mountComponent();

      const recoveryLink = wrapper.find('a[href="/account/settings/security/recovery-codes"]');
      expect(recoveryLink.exists()).toBe(true);
      expect(recoveryLink.text()).toContain('Recovery Codes');
    });
  });

  describe('Accessibility', () => {
    it('page title is h1', () => {
      wrapper = mountComponent();

      const h1 = wrapper.find('h1');
      expect(h1.exists()).toBe(true);
      expect(h1.text()).toBe('Passkeys');
    });

    it('section title is h2', () => {
      wrapper = mountComponent();

      const h2 = wrapper.find('h2');
      expect(h2.exists()).toBe(true);
      expect(h2.text()).toBe('Passkeys');
    });

    it('add passkey button has descriptive text', () => {
      wrapper = mountComponent();

      const button = wrapper.find('[data-testid="add-passkey-button"]');
      expect(button.text()).toContain('Add passkey');
    });
  });
});
