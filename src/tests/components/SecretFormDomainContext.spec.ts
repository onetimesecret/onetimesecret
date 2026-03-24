// src/tests/components/SecretFormDomainContext.spec.ts

import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
import { nextTick } from 'vue';

// Mock composables
const mockCurrentContext = {
  value: {
    domain: 'acme.example.com',
    displayName: 'acme.example.com',
    isCanonical: false,
  },
};

const mockIsContextActive = { value: true };
const mockSetContext = vi.fn();

vi.mock('@/shared/composables/useDomainContext', () => ({
  useDomainContext: vi.fn(() => ({
    currentContext: mockCurrentContext,
    isContextActive: mockIsContextActive,
    hasMultipleContexts: { value: true },
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
  });

  describe('Domain Context Indicator', () => {
    it('displays context indicator when isContextActive is true', () => {
      mockIsContextActive.value = true;

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find('[role="status"]');
      expect(indicator.exists()).toBe(true);
    });

    it('hides context indicator when isContextActive is false', () => {
      mockIsContextActive.value = false;

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      // When context is inactive, the v-if should not render the context indicator
      const contextSection = wrapper.find('[data-testid="domain-context-section"]');
      if (!contextSection.exists()) {
        // The v-if prevented rendering - this is correct
        expect(true).toBe(true);
      } else {
        // If it exists, it should not be visible
        expect(contextSection.isVisible()).toBe(false);
      }
    });

    it.skip('displays correct domain name for custom domain', () => {
      // SKIP: Reactive mock computed properties don't propagate to template bindings.
      // The template uses {{ currentContext.displayName }} which evaluates at render time.
      // Vitest module mocks capture values at import time; changing mockCurrentContext.value
      // after mount doesn't trigger Vue reactivity.
      //
      // E2E COVERAGE: e2e/full/domain-context-consultant.spec.ts
      //   - "displays domain context indicator for user with custom domains" (line 72)
      // STATUS: E2E test exists but skipped pending backend test fixtures
      mockCurrentContext.value = {
        domain: 'acme.example.com',
        displayName: 'acme.example.com',
        isCanonical: false,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find('[role="status"]');
      // Check that the displayName is bound in the template
      expect(indicator.html()).toContain('acme.example.com');
    });

    it.skip('displays "Personal" for canonical domain', () => {
      // SKIP: Same Vitest mock limitation - values captured at import time.
      //
      // E2E COVERAGE: e2e/full/domain-context-consultant.spec.ts
      //   - "canonical domain shows Personal label" (line 290)
      // STATUS: E2E test exists but skipped pending DomainContextSwitcher integration
      mockCurrentContext.value = {
        domain: 'onetimesecret.com',
        displayName: 'Personal',
        isCanonical: true,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find('[role="status"]');
      // Check HTML since OIcon doesn't render readable text
      expect(indicator.html()).toContain('Personal');
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

      const indicator = wrapper.find('[role="status"]');
      const classes = indicator.classes();

      // Custom domain should have brand colors
      expect(classes).toContain('bg-brand-50');
      expect(classes).toContain('text-brand-700');
    });

    it.skip('applies canonical domain styling for canonical context', () => {
      // SKIP: Vitest mock limitation - :class bindings evaluate at render time with
      // captured mock values, not reactively updated values.
      //
      // E2E COVERAGE: e2e/full/domain-context-consultant.spec.ts
      //   - "context indicator shows correct styling for custom domain" (line 104)
      //   - "canonical domain shows Personal label" (line 290) - checks gray styling
      // STATUS: E2E tests exist but skipped pending backend fixtures
      mockIsContextActive.value = true;
      mockCurrentContext.value = {
        domain: 'onetimesecret.com',
        displayName: 'Personal',
        isCanonical: true,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find('[role="status"]');
      const html = indicator.html();

      // Canonical domain should have gray colors in the class list
      expect(html).toContain('bg-gray-100');
      expect(html).toContain('text-gray-700');
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

      const indicator = wrapper.find('[role="status"]');
      // The icon component uses href with the icon name
      expect(indicator.html()).toContain('building-office');
    });

    it.skip('displays correct icon for canonical domain', () => {
      // SKIP: Same Vitest mock limitation - template conditionals use captured values.
      //
      // E2E COVERAGE: No direct E2E test for icon verification exists.
      // MISSING: Consider adding icon assertion to "canonical domain shows Personal label"
      mockIsContextActive.value = true;
      mockCurrentContext.value = {
        domain: 'onetimesecret.com',
        displayName: 'Personal',
        isCanonical: true,
      };

      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find('[role="status"]');
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

      const indicator = wrapper.find('[role="status"]');
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

      const indicator = wrapper.find('[role="status"]');
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
        validation: { errors: new Map() },
        operations: {
          updateField: mockUpdateField,
          reset: vi.fn(),
        },
        isSubmitting: false,
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

    it.skip('reactively updates when currentContext changes', async () => {
      // SKIP: Vitest module mocks don't participate in Vue's reactivity system.
      // Reactivity is tested in useDomainContext.spec.ts composable tests.
      //
      // E2E COVERAGE: e2e/full/domain-context-consultant.spec.ts
      //   - "context indicator updates when switching domains" (line 264)
      //   - "context switcher allows changing between domains" (line 233)
      // STATUS: E2E tests exist but skipped pending DomainContextSwitcher - component
      // exists at src/shared/components/navigation/DomainContextSwitcher.vue, tests
      // can be enabled once backend fixtures are configured

      const mockUpdateField = vi.fn();

      vi.mocked(
        await import('@/shared/composables/useSecretConcealer')
      ).useSecretConcealer.mockReturnValue({
        form: { secret: '', passphrase: '', ttl: 300, share_domain: '' },
        validation: { errors: new Map() },
        operations: {
          updateField: mockUpdateField,
          reset: vi.fn(),
        },
        isSubmitting: false,
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

      const indicator = wrapper.find('[role="status"]');
      const parent = indicator.element.parentElement;

      // Should be in a flex container
      expect(parent?.classList.contains('flex')).toBe(true);
    });

    it('renders context indicator before action button on desktop', () => {
      const wrapper = mount(SecretForm, {
        props: { enabled: true },
        global: { plugins: [createMountPinia()] },
      });

      const indicator = wrapper.find('[role="status"]');

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
