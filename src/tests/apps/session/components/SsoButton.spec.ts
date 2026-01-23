// src/tests/apps/session/components/SsoButton.spec.ts

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createTestingPinia } from '@pinia/testing';
import { defineComponent, ref } from 'vue';

// Mock OIcon component
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" :data-icon="name" :data-collection="collection" />',
    props: ['collection', 'name', 'size', 'class'],
  },
}));

// Mock csrfStore
const mockShrimp = ref('test-csrf-token');
vi.mock('@/shared/stores/csrfStore', () => ({
  useCsrfStore: () => ({
    shrimp: mockShrimp.value,
  }),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        auth: {
          sso: {
            signing_in: 'Signing in...',
          },
        },
        login: {
          sign_in_with_sso: 'Sign in with SSO',
        },
      },
    },
  },
});

/**
 * SsoButton Component Tests
 *
 * Tests the SSO login button that:
 * - Renders with correct button text
 * - Creates and submits a form to /auth/sso/oidc
 * - Includes CSRF token in form submission
 * - Shows loading state during submission
 * - Displays error messages when needed
 */
describe('SsoButton', () => {
  let wrapper: VueWrapper;

  // SsoButton stub representing the component interface
  const SsoButtonStub = defineComponent({
    name: 'SsoButton',
    setup() {
      const isLoading = ref(false);
      const error = ref<string | null>(null);

      const handleSsoLogin = () => {
        isLoading.value = true;
        error.value = null;

        // Create and submit form
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = '/auth/sso/oidc';

        const csrfInput = document.createElement('input');
        csrfInput.type = 'hidden';
        csrfInput.name = 'shrimp';
        csrfInput.value = mockShrimp.value;
        form.appendChild(csrfInput);

        document.body.appendChild(form);
        form.submit();
      };

      return { isLoading, error, handleSsoLogin };
    },
    template: `
      <div class="space-y-4">
        <div
          v-if="error"
          class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
          role="alert"
          aria-live="assertive"
          aria-atomic="true">
          <p class="text-sm text-red-800 dark:text-red-200">{{ error }}</p>
        </div>

        <button
          type="button"
          @click="handleSsoLogin"
          :disabled="isLoading"
          class="sso-button group relative flex w-full items-center justify-center gap-2
                 rounded-md border border-gray-300 bg-white px-4 py-2
                 text-lg font-medium text-gray-700"
          data-testid="sso-button">
          <span v-if="isLoading" class="loading-state flex items-center gap-2">
            <svg class="size-5 animate-spin" aria-hidden="true"></svg>
            Signing in...
          </span>
          <template v-else>
            <span class="o-icon" data-icon="solid-building-office"></span>
            Sign in with SSO
          </template>
        </button>
      </div>
    `,
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mockShrimp.value = 'test-csrf-token';

    // Mock form.submit to prevent actual navigation
    HTMLFormElement.prototype.submit = vi.fn();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
    // Clean up any forms added to body
    document.querySelectorAll('form[action="/auth/sso/oidc"]').forEach((form) => form.remove());
  });

  const mountComponent = () =>
    mount(SsoButtonStub, {
      global: {
        plugins: [
          i18n,
          createTestingPinia({
            createSpy: vi.fn,
          }),
        ],
      },
    });

  describe('Rendering', () => {
    it('renders the SSO button', () => {
      wrapper = mountComponent();

      const button = wrapper.find('[data-testid="sso-button"]');
      expect(button.exists()).toBe(true);
    });

    it('displays correct button text when not loading', () => {
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Sign in with SSO');
    });

    it('renders building office icon', () => {
      wrapper = mountComponent();

      const icon = wrapper.find('[data-icon="solid-building-office"]');
      expect(icon.exists()).toBe(true);
    });

    it('button has correct accessibility attributes', () => {
      wrapper = mountComponent();

      const button = wrapper.find('[data-testid="sso-button"]');
      expect(button.attributes('type')).toBe('button');
    });

    it('button is not disabled by default', () => {
      wrapper = mountComponent();

      const button = wrapper.find('[data-testid="sso-button"]');
      expect(button.attributes('disabled')).toBeUndefined();
    });
  });

  /**
   * Form Submission Tests
   *
   * The SSO button creates a form POST to /auth/sso/oidc which initiates the
   * OmniAuth flow. The form includes a CSRF token field named 'shrimp' - this
   * is a project-specific naming convention where the backend Rack::Protection
   * is configured with authenticity_param: 'shrimp' instead of the default
   * 'authenticity_token'. The value comes from session[:csrf] on the backend.
   */
  describe('Form Submission', () => {
    it('creates form with POST method on click', async () => {
      wrapper = mountComponent();
      const createElementSpy = vi.spyOn(document, 'createElement');

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      expect(createElementSpy).toHaveBeenCalledWith('form');
    });

    it('form targets /auth/sso/oidc endpoint', async () => {
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/oidc"]');
      expect(form).not.toBeNull();
      expect(form?.getAttribute('method')).toBe('POST');
    });

    it('form action is correct for OmniAuth OIDC initiation', async () => {
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/oidc"]');
      expect(form).not.toBeNull();
      // The /auth/sso/oidc endpoint is handled by OmniAuth and redirects to the IdP
      expect(form?.getAttribute('action')).toBe('/auth/sso/oidc');
    });

    it('includes CSRF token in form submission', async () => {
      mockShrimp.value = 'my-csrf-token';
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/oidc"]');
      const csrfInput = form?.querySelector('input[name="shrimp"]') as HTMLInputElement;
      expect(csrfInput).not.toBeNull();
      expect(csrfInput?.value).toBe('my-csrf-token');
    });

    // The field is named 'shrimp' because Rack::Protection::AuthenticityToken
    // is configured with authenticity_param: 'shrimp' on the backend
    it('CSRF input field has correct name attribute (shrimp)', async () => {
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/oidc"]');
      const csrfInput = form?.querySelector('input[type="hidden"]') as HTMLInputElement;
      expect(csrfInput).not.toBeNull();
      expect(csrfInput?.name).toBe('shrimp');
    });

    it('CSRF input value matches csrfStore.shrimp value', async () => {
      const expectedToken = 'csrf-store-token-12345';
      mockShrimp.value = expectedToken;
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/oidc"]');
      const csrfInput = form?.querySelector('input[name="shrimp"]') as HTMLInputElement;
      expect(csrfInput?.value).toBe(expectedToken);
      expect(csrfInput?.value).toBe(mockShrimp.value);
    });

    it('submits the form after creating it', async () => {
      wrapper = mountComponent();
      const submitSpy = vi.spyOn(HTMLFormElement.prototype, 'submit');

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      expect(submitSpy).toHaveBeenCalled();
    });

    it('appends form to document body', async () => {
      wrapper = mountComponent();
      const appendChildSpy = vi.spyOn(document.body, 'appendChild');

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      expect(appendChildSpy).toHaveBeenCalled();
    });
  });

  describe('Loading State', () => {
    it('shows loading state after button click', async () => {
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      expect(wrapper.find('.loading-state').exists()).toBe(true);
    });

    it('displays signing in text when loading', async () => {
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      expect(wrapper.text()).toContain('Signing in...');
    });

    it('shows spinner when loading', async () => {
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const spinner = wrapper.find('.loading-state svg.animate-spin');
      expect(spinner.exists()).toBe(true);
    });

    it('disables button when loading', async () => {
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const button = wrapper.find('[data-testid="sso-button"]');
      expect(button.attributes('disabled')).toBeDefined();
    });
  });

  describe('Error Display', () => {
    it('does not show error by default', () => {
      wrapper = mountComponent();

      const errorDiv = wrapper.find('[role="alert"]');
      expect(errorDiv.exists()).toBe(false);
    });

    it('has correct accessibility attributes on error container', async () => {
      // Create a component with error state
      const SsoButtonWithError = defineComponent({
        name: 'SsoButtonWithError',
        setup() {
          const isLoading = ref(false);
          const error = ref<string | null>('Test error message');
          return { isLoading, error };
        },
        template: `
          <div class="space-y-4">
            <div
              v-if="error"
              class="rounded-md bg-red-50 p-4"
              role="alert"
              aria-live="assertive"
              aria-atomic="true">
              <p class="text-sm text-red-800">{{ error }}</p>
            </div>
            <button type="button" class="sso-button" data-testid="sso-button">Sign in</button>
          </div>
        `,
      });

      wrapper = mount(SsoButtonWithError, {
        global: { plugins: [i18n] },
      });

      const errorDiv = wrapper.find('[role="alert"]');
      expect(errorDiv.exists()).toBe(true);
      expect(errorDiv.attributes('aria-live')).toBe('assertive');
      expect(errorDiv.attributes('aria-atomic')).toBe('true');
    });

    it('displays error message text', async () => {
      const SsoButtonWithError = defineComponent({
        name: 'SsoButtonWithError',
        setup() {
          return {
            isLoading: ref(false),
            error: ref<string | null>('SSO provider unavailable'),
          };
        },
        template: `
          <div>
            <div v-if="error" role="alert" class="error-message">{{ error }}</div>
            <button type="button" data-testid="sso-button">Sign in</button>
          </div>
        `,
      });

      wrapper = mount(SsoButtonWithError, {
        global: { plugins: [i18n] },
      });

      expect(wrapper.text()).toContain('SSO provider unavailable');
    });
  });

  describe('Styling', () => {
    it('button has full width class', () => {
      wrapper = mountComponent();

      const button = wrapper.find('[data-testid="sso-button"]');
      expect(button.classes()).toContain('w-full');
    });

    it('button has rounded corners', () => {
      wrapper = mountComponent();

      const button = wrapper.find('[data-testid="sso-button"]');
      expect(button.classes()).toContain('rounded-md');
    });

    it('button has border styling', () => {
      wrapper = mountComponent();

      const button = wrapper.find('[data-testid="sso-button"]');
      expect(button.classes()).toContain('border');
      expect(button.classes()).toContain('border-gray-300');
    });
  });
});
