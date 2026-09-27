// src/tests/components/SecretFormDomainContext.spec.ts

import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
import { nextTick, reactive, ref } from 'vue';

const INDICATOR = '[data-testid="secret-domain-context-indicator"]';

// Mock composables. These are real refs because useDomainContext returns
// computeds: the template unwraps a ref, but not a plain `{ value }` object, so
// with plain objects every `currentContext.*` binding in the template read
// undefined.
const mockCurrentContext = ref({
  domain: 'acme.example.com',
  displayName: 'acme.example.com',
  isCanonical: false,
});

const mockIsContextActive = ref(true);
const mockHasMultipleContexts = ref(true);
const mockSetContext = vi.fn();

vi.mock('@/shared/composables/useDomainContext', () => ({
  useDomainContext: vi.fn(() => ({
    currentContext: mockCurrentContext,
    isContextActive: mockIsContextActive,
    hasMultipleContexts: mockHasMultipleContexts,
    availableDomains: { value: ['acme.example.com', 'widgets.example.com', 'onetimesecret.com'] },
    setContext: mockSetContext,
    resetContext: vi.fn(),
  })),
}));

// Mock other composables used by SecretForm
vi.mock('@/shared/composables/useSecretConcealer', () => ({
  useSecretConcealer: vi.fn(() => ({
    form: { secret: '', passphrase: '', ttl: 300, share_domain: '' },
    validation: { errors: new Map() },
    operations: {
      updateField: vi.fn(),
      reset: vi.fn(),
    },
    isSubmitting: false,
    submit: vi.fn(),
  })),
}));

vi.mock('@/shared/composables/usePrivacyOptions', () => ({
  usePrivacyOptions: vi.fn(() => ({
    state: { passphraseVisibility: false },
    lifetimeOptions: [
      { label: '5 minutes', value: 300 },
      { label: '1 hour', value: 3600 },
    ],
    updatePassphrase: vi.fn(),
    updateTtl: vi.fn(),
    updateRecipient: vi.fn(),
    togglePassphraseVisibility: vi.fn(),
  })),
}));


vi.mock('vue-router', () => ({
  useRouter: vi.fn(() => ({
    push: vi.fn(),
  })),
}));

vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string, params?: any) => {
      if (params && params.domain) {
        return `${key} - ${params.domain}`;
      }
      return key;
    }),
  })),
}));

// Helper to create testing pinia with bootstrap state
const createMountPinia = () =>
  createTestingPinia({
    createSpy: vi.fn,
    initialState: {
      bootstrap: {
        secret_options: {
          passphrase: {
            required: false,
            minimum_length: 8,
            enforce_complexity: false,
          },
        },
      },
    },
  });

describe('SecretForm - Domain Context Integration', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Reset mock context state
    mockCurrentContext.value = {
      domain: 'acme.example.com',
      displayName: 'acme.example.com',
      isCanonical: false,
    };
    mockIsContextActive.value = true;
    mockHasMultipleContexts.value = true;
  });

  describe('Domain Context Indicator', () => {
    it('renders the indicator for a custom domain context', () => {
      mockIsContextActive.value = true;

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      expect(wrapper.find(INDICATOR).exists()).toBe(true);
    });

    // domains_enabled: false makes useDomainContext report isContextActive
    // false (covered in useDomainContext.spec.ts). The form then has no domain
    // context to show.
    it('does not render the indicator when domains are disabled', () => {
      mockIsContextActive.value = false;

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      expect(wrapper.find(INDICATOR).exists()).toBe(false);
      expect(wrapper.text()).not.toContain('web.LABELS.creating_links_for');
    });

    // Domains enabled with no custom domains: the canonical domain is the only
    // possible context, so there is no domain choice to indicate.
    it('does not render the indicator when only the canonical domain exists', () => {
      mockIsContextActive.value = true;
      mockHasMultipleContexts.value = false;
      mockCurrentContext.value = {
        domain: 'onetimesecret.com',
        displayName: 'onetimesecret.com',
        isCanonical: true,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      expect(wrapper.find(INDICATOR).exists()).toBe(false);
      expect(wrapper.text()).not.toContain('web.LABELS.creating_links_for');
    });

    it('hides context indicator on a custom domain (single fixed domain)', () => {
      mockIsContextActive.value = true;

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: {
          plugins: [
            createTestingPinia({
              createSpy: vi.fn,
              initialState: {
                bootstrap: {
                  domain_strategy: 'custom',
                  display_domain: 'acme.example.com',
                  secret_options: {
                    passphrase: {
                      required: false,
                      minimum_length: 8,
                      enforce_complexity: false,
                    },
                  },
                },
              },
            }),
          ],
        },
      });

      // The "Creating links for" badge is noise when only one domain is possible.
      expect(wrapper.find(INDICATOR).exists()).toBe(false);
    });

    it('displays correct domain name for custom domain', () => {
      mockCurrentContext.value = {
        domain: 'acme.example.com',
        displayName: 'acme.example.com',
        isCanonical: false,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      expect(wrapper.find(INDICATOR).text()).toContain('acme.example.com');
    });
  });

  describe('Domain Context Styling', () => {
    it('applies custom domain styling for non-canonical context', () => {
      mockCurrentContext.value = {
        domain: 'acme.example.com',
        displayName: 'acme.example.com',
        isCanonical: false,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find(INDICATOR);
      const classes = indicator.classes();

      // Custom domain should have brand colors
      expect(classes).toContain('bg-brand-50');
      expect(classes).toContain('text-brand-700');
    });

    it('applies canonical domain styling for canonical context', () => {
      mockIsContextActive.value = true;
      mockCurrentContext.value = {
        domain: 'onetimesecret.com',
        displayName: 'onetimesecret.com',
        isCanonical: true,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const classes = wrapper.find(INDICATOR).classes();

      // Canonical domain should have gray colors, not the brand ones
      expect(classes).toContain('bg-gray-100');
      expect(classes).toContain('text-gray-700');
      expect(classes).not.toContain('bg-brand-50');
    });

    it('displays correct icon for custom domain', () => {
      mockCurrentContext.value = {
        domain: 'acme.example.com',
        displayName: 'acme.example.com',
        isCanonical: false,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find(INDICATOR);
      // The icon component uses href with the icon name
      expect(indicator.html()).toContain('building-office');
    });

    it('displays correct icon for canonical domain', () => {
      mockIsContextActive.value = true;
      mockCurrentContext.value = {
        domain: 'onetimesecret.com',
        displayName: 'onetimesecret.com',
        isCanonical: true,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find(INDICATOR);
      // The icon component uses href with the icon name
      expect(indicator.html()).toContain('user-circle');
    });
  });

  describe('Accessibility', () => {
    it('has proper ARIA attributes on context indicator', () => {
      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find(INDICATOR);
      expect(indicator.attributes('role')).toBe('status');
      expect(indicator.attributes('aria-label')).toBeTruthy();
    });

    it('includes descriptive aria-label with domain name', () => {
      mockCurrentContext.value = {
        domain: 'acme.example.com',
        displayName: 'acme.example.com',
        isCanonical: false,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find(INDICATOR);
      const ariaLabel = indicator.attributes('aria-label');
      // The aria-label should reference the i18n key with domain parameter
      expect(ariaLabel).toBeTruthy();
      expect(ariaLabel).toContain('scope_indicator');
    });
  });

  describe('Context Change Handling', () => {
    it('updates share_domain field when context changes', async () => {
      const mockUpdateField = vi.fn();

      vi.mocked(
        await import('@/shared/composables/useSecretConcealer')
      ).useSecretConcealer.mockReturnValue({
        form: { secret: '', passphrase: '', ttl: 300, share_domain: '' },
        validation: {
          errors: reactive(new Map()),
          validate: vi.fn(() => true),
          validateRecipient: vi.fn(() => true),
        },
        operations: {
          updateField: mockUpdateField,
          reset: vi.fn(),
        },
        isSubmitting: ref(false),
        submit: vi.fn(),
      });

      mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      await nextTick();

      // Should initialize with current context domain
      expect(mockUpdateField).toHaveBeenCalledWith('share_domain', 'acme.example.com');
    });

    it('reactively updates when currentContext changes', async () => {
      const mockUpdateField = vi.fn();

      vi.mocked(
        await import('@/shared/composables/useSecretConcealer')
      ).useSecretConcealer.mockReturnValue({
        form: { secret: '', passphrase: '', ttl: 300, share_domain: '' },
        validation: {
          errors: reactive(new Map()),
          validate: vi.fn(() => true),
          validateRecipient: vi.fn(() => true),
        },
        operations: {
          updateField: mockUpdateField,
          reset: vi.fn(),
        },
        isSubmitting: ref(false),
        submit: vi.fn(),
      });

      mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      // Change the context
      mockCurrentContext.value = {
        domain: 'widgets.example.com',
        displayName: 'widgets.example.com',
        isCanonical: false,
      };

      await nextTick();

      // Watcher should trigger updateField
      expect(mockUpdateField).toHaveBeenCalledWith('share_domain', 'widgets.example.com');
    });
  });

  describe('Layout and Positioning', () => {
    it('positions context indicator correctly in the form footer', () => {
      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find(INDICATOR);
      const parent = indicator.element.parentElement;

      // Should be in a flex container
      expect(parent?.classList.contains('flex')).toBe(true);
    });

    it('renders context indicator before action button on desktop', () => {
      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find(INDICATOR);

      // Check that order-1 class is applied for proper ordering
      const parentDiv = indicator.element.parentElement;
      expect(parentDiv?.classList.contains('order-1')).toBe(true);
    });

    it('truncates long domain names with ellipsis', () => {
      mockCurrentContext.value = {
        domain: 'very-long-domain-name.example.com',
        displayName: 'very-long-domain-name.example.com',
        isCanonical: false,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const domainText = wrapper.find('.max-w-\\[180px\\]');
      expect(domainText.exists()).toBe(true);
      expect(domainText.classes()).toContain('truncate');
    });
  });
});
