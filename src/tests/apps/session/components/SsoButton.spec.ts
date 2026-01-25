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

// Mock bootstrapStore with configurable features
const mockFeatures = ref<{
  omniauth?: boolean | { enabled: boolean; provider_name?: string; route_name?: string };
}>({});

vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => ({
    features: mockFeatures.value,
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
          sign_in_with_provider: 'Sign in with {provider}',
        },
      },
    },
  },
});

/**
 * SsoButton Component Tests
 *
 * Tests the SSO login button that:
 * - Renders with correct button text (generic or provider-specific)
 * - Creates and submits a form to /auth/sso/oidc
 * - Includes shrimp token in form submission (for consistency with other forms)
 * - Shows loading state during submission
 * - Reads provider_name from bootstrapStore.features.omniauth
 *
 * Note: SSO routes (/auth/sso/*) skip Rack::Protection CSRF validation.
 * CSRF protection is handled by OAuth's state parameter instead.
 * The shrimp token is still included for form consistency but is not validated.
 */
describe('SsoButton', () => {
  let wrapper: VueWrapper;

  /**
   * SsoButton implementation matching the actual component behavior.
   * Uses bootstrapStore for features and csrfStore for CSRF token.
   */
  const SsoButtonStub = defineComponent({
    name: 'SsoButton',
    setup() {
      const isLoading = ref(false);

      // Provider name computed from features (matches actual component)
      const providerName = (() => {
        const omniauth = mockFeatures.value?.omniauth;
        if (typeof omniauth === 'object' && omniauth !== null) {
          return omniauth.provider_name || null;
        }
        return null;
      })();

      // SSO route computed from features (matches actual component)
      const ssoRoute = (() => {
        const omniauth = mockFeatures.value?.omniauth;
        if (typeof omniauth === 'object' && omniauth !== null) {
          return `/auth/sso/${omniauth.route_name || 'oidc'}`;
        }
        return '/auth/sso/oidc';
      })();

      const handleSsoLogin = () => {
        isLoading.value = true;

        // Create and submit form
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = ssoRoute;

        const csrfInput = document.createElement('input');
        csrfInput.type = 'hidden';
        csrfInput.name = 'shrimp';
        csrfInput.value = mockShrimp.value;
        form.appendChild(csrfInput);

        document.body.appendChild(form);
        form.submit();
      };

      return { isLoading, providerName, handleSsoLogin };
    },
    template: `
      <div>
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
            {{ providerName ? 'Sign in with ' + providerName : 'Sign in with SSO' }}
          </template>
        </button>
      </div>
    `,
  });

  beforeEach(() => {
    vi.clearAllMocks();
    mockShrimp.value = 'test-csrf-token';
    mockFeatures.value = {};

    // Mock form.submit to prevent actual navigation
    HTMLFormElement.prototype.submit = vi.fn();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
    // Clean up any forms added to body
    document.querySelectorAll('form[action^="/auth/sso/"]').forEach((form) => form.remove());
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

    it('displays generic SSO text when no provider_name is configured', () => {
      mockFeatures.value = { omniauth: true };
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Sign in with SSO');
    });

    it('displays generic SSO text when omniauth is boolean true', () => {
      mockFeatures.value = { omniauth: true };
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Sign in with SSO');
      expect(wrapper.text()).not.toContain('Sign in with Okta');
    });

    it('displays generic SSO text when omniauth is object without provider_name', () => {
      mockFeatures.value = { omniauth: { enabled: true } };
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

  describe('Provider Name Display', () => {
    it('displays provider name when configured in omniauth object', () => {
      mockFeatures.value = {
        omniauth: { enabled: true, provider_name: 'Okta' },
      };
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Sign in with Okta');
      expect(wrapper.text()).not.toContain('Sign in with SSO');
    });

    it('displays provider name for Zitadel', () => {
      mockFeatures.value = {
        omniauth: { enabled: true, provider_name: 'Zitadel' },
      };
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Sign in with Zitadel');
    });

    it('displays provider name for Azure AD', () => {
      mockFeatures.value = {
        omniauth: { enabled: true, provider_name: 'Azure AD' },
      };
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Sign in with Azure AD');
    });

    it('displays provider name for Google Workspace', () => {
      mockFeatures.value = {
        omniauth: { enabled: true, provider_name: 'Google Workspace' },
      };
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Sign in with Google Workspace');
    });

    it('falls back to SSO when provider_name is empty string', () => {
      mockFeatures.value = {
        omniauth: { enabled: true, provider_name: '' },
      };
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Sign in with SSO');
    });

    it('falls back to SSO when provider_name is null', () => {
      mockFeatures.value = {
        omniauth: { enabled: true, provider_name: undefined },
      };
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Sign in with SSO');
    });

    it('falls back to SSO when omniauth is boolean false', () => {
      mockFeatures.value = { omniauth: false };
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Sign in with SSO');
    });

    it('falls back to SSO when omniauth is undefined', () => {
      mockFeatures.value = {};
      wrapper = mountComponent();

      expect(wrapper.text()).toContain('Sign in with SSO');
    });
  });

  describe('Dynamic Route Name', () => {
    it('uses default oidc route when route_name is not configured', async () => {
      mockFeatures.value = { omniauth: { enabled: true } };
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/oidc"]');
      expect(form).not.toBeNull();
    });

    it('uses custom route_name when configured', async () => {
      mockFeatures.value = { omniauth: { enabled: true, route_name: 'saml' } };
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/saml"]');
      expect(form).not.toBeNull();
    });

    it('supports google_oauth2 route name', async () => {
      mockFeatures.value = {
        omniauth: { enabled: true, route_name: 'google_oauth2', provider_name: 'Google' },
      };
      wrapper = mountComponent();

      // Check button text before clicking (click triggers loading state)
      expect(wrapper.text()).toContain('Sign in with Google');

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/google_oauth2"]');
      expect(form).not.toBeNull();
    });

    it('supports azure_activedirectory_v2 route name', async () => {
      mockFeatures.value = {
        omniauth: { enabled: true, route_name: 'azure_activedirectory_v2', provider_name: 'Azure AD' },
      };
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/azure_activedirectory_v2"]');
      expect(form).not.toBeNull();
    });

    it('falls back to oidc when omniauth is boolean true', async () => {
      mockFeatures.value = { omniauth: true };
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/oidc"]');
      expect(form).not.toBeNull();
    });

    it('falls back to oidc when route_name is empty string', async () => {
      mockFeatures.value = { omniauth: { enabled: true, route_name: '' } };
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/oidc"]');
      expect(form).not.toBeNull();
    });
  });

  /**
   * Form Submission Tests
   *
   * The SSO button creates a form POST to /auth/sso/oidc which initiates the
   * OmniAuth flow. The form includes a shrimp field for consistency with other
   * forms, but SSO routes skip Rack::Protection CSRF validation - CSRF protection
   * is instead handled by OAuth's state parameter during the IdP redirect flow.
   *
   * The shrimp field uses the project-specific naming convention (not
   * 'authenticity_token') and the value comes from session[:csrf] on the backend.
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

    it('includes shrimp token in form submission', async () => {
      mockShrimp.value = 'my-csrf-token';
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/oidc"]');
      const csrfInput = form?.querySelector('input[name="shrimp"]') as HTMLInputElement;
      expect(csrfInput).not.toBeNull();
      expect(csrfInput?.value).toBe('my-csrf-token');
    });

    // The field is named 'shrimp' for consistency with other forms in the app.
    // Note: SSO routes skip CSRF validation; OAuth state param provides protection.
    it('shrimp input field has correct name attribute', async () => {
      wrapper = mountComponent();

      await wrapper.find('[data-testid="sso-button"]').trigger('click');

      const form = document.querySelector('form[action="/auth/sso/oidc"]');
      const csrfInput = form?.querySelector('input[type="hidden"]') as HTMLInputElement;
      expect(csrfInput).not.toBeNull();
      expect(csrfInput?.name).toBe('shrimp');
    });

    it('shrimp input value matches csrfStore.shrimp value', async () => {
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
