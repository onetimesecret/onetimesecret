// src/tests/apps/workspace/components/domains/DomainForm.spec.ts
//
// Tests for DomainForm.vue covering:
// 1. Form renders with DomainInput component
// 2. Empty submission shows error
// 3. Invalid domain shows error
// 4. Valid domain emits submit event with validated domain
// 5. Back button emits back event
// 6. Submit button shows loading state when isSubmitting
// 7. Error display component shows when localError exists

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import DomainForm from '@/apps/workspace/components/domains/DomainForm.vue';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

vi.mock('@/apps/workspace/components/domains/DomainInput.vue', () => ({
  default: {
    name: 'DomainInput',
    template: `
      <div data-testid="domain-input-wrapper">
        <input
          data-testid="domain-input-field"
          :value="modelValue"
          @input="$emit('update:modelValue', $event.target.value)"
          :placeholder="placeholder"
        />
      </div>
    `,
    props: ['modelValue', 'placeholder', 'isValid', 'autofocus', 'required'],
    emits: ['update:modelValue'],
  },
}));

vi.mock('@/shared/components/ui/ErrorDisplay.vue', () => ({
  default: {
    name: 'ErrorDisplay',
    template: '<div data-testid="error-display" :data-message="error?.message">{{ error?.message }}</div>',
    props: ['error'],
  },
}));

// ---------------------------------------------------------------------------
// i18n setup
// ---------------------------------------------------------------------------

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {
    en: {
      web: {
        domains: {
          please_enter_a_domain_name: 'Please enter a domain name',
          secrets_example_dot_com: 'secrets.example.com',
        },
        COMMON: {
          e_g_example: 'e.g.',
          back: 'Back',
          continue: 'Continue',
          adding_ellipses: 'Adding',
        },
        layout: {
          go_back_to_previous_page: 'Go back to previous page',
        },
      },
    },
  },
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('DomainForm', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    if (wrapper) {
      wrapper.unmount();
    }
  });

  const mountComponent = (props: { isSubmitting?: boolean } = {}) => {
    return mount(DomainForm, {
      props: {
        isSubmitting: props.isSubmitting ?? false,
      },
      global: {
        plugins: [i18n],
      },
    });
  };

  // -------------------------------------------------------------------------
  // Form rendering
  // -------------------------------------------------------------------------

  describe('Form rendering', () => {
    it('renders the form element', () => {
      wrapper = mountComponent();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      expect(form.exists()).toBe(true);
    });

    it('renders DomainInput component', () => {
      wrapper = mountComponent();

      // The component has data-testid="domain-input" on the DomainInput component itself
      // Check for the input field within the form
      const domainInput = wrapper.find('[data-testid="domain-input-field"]');
      expect(domainInput.exists()).toBe(true);
    });

    it('renders back button', () => {
      wrapper = mountComponent();

      const backButton = wrapper.find('[data-testid="domain-add-cancel-btn"]');
      expect(backButton.exists()).toBe(true);
      expect(backButton.text()).toContain('Back');
    });

    it('renders submit button', () => {
      wrapper = mountComponent();

      const submitButton = wrapper.find('[data-testid="domain-add-submit"]');
      expect(submitButton.exists()).toBe(true);
      expect(submitButton.text()).toContain('Continue');
    });

    it('does not show error display initially', () => {
      wrapper = mountComponent();

      const errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // Form validation - empty submission
  // -------------------------------------------------------------------------

  describe('Empty submission', () => {
    it('shows error when submitting empty form', async () => {
      wrapper = mountComponent();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      const errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(true);
      expect(errorDisplay.attributes('data-message')).toBe('Please enter a domain name');
    });

    it('does not emit submit event when form is empty', async () => {
      wrapper = mountComponent();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('submit')).toBeFalsy();
    });

    it('shows error when submitting whitespace-only domain', async () => {
      wrapper = mountComponent();

      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('   ');
      await flushPromises();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      const errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // Form validation - invalid domain
  // -------------------------------------------------------------------------

  describe('Invalid domain', () => {
    it('shows error for domain shorter than 3 characters', async () => {
      wrapper = mountComponent();

      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('ab');
      await flushPromises();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      const errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(true);
      expect(wrapper.emitted('submit')).toBeFalsy();
    });

    it('shows error for domain starting with special character', async () => {
      wrapper = mountComponent();

      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('-example.com');
      await flushPromises();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      const errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(true);
    });

    it('shows error for domain ending with special character', async () => {
      wrapper = mountComponent();

      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('example.com-');
      await flushPromises();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      const errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(true);
    });

    it('shows error for domain with invalid characters', async () => {
      wrapper = mountComponent();

      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('example@domain.com');
      await flushPromises();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      const errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(true);
    });
  });

  // -------------------------------------------------------------------------
  // Form validation - valid domain
  // -------------------------------------------------------------------------

  describe('Valid domain submission', () => {
    it('emits submit event with validated domain', async () => {
      wrapper = mountComponent();

      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('example.com');
      await flushPromises();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('submit')).toBeTruthy();
      expect(wrapper.emitted('submit')![0]).toEqual(['example.com']);
    });

    it('accepts domain with subdomain', async () => {
      wrapper = mountComponent();

      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('secrets.example.com');
      await flushPromises();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('submit')).toBeTruthy();
      expect(wrapper.emitted('submit')![0]).toEqual(['secrets.example.com']);
    });

    it('accepts domain with hyphens', async () => {
      wrapper = mountComponent();

      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('my-company.example.com');
      await flushPromises();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('submit')).toBeTruthy();
      expect(wrapper.emitted('submit')![0]).toEqual(['my-company.example.com']);
    });

    it('accepts domain with underscores', async () => {
      wrapper = mountComponent();

      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('my_company.example.com');
      await flushPromises();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      expect(wrapper.emitted('submit')).toBeTruthy();
      expect(wrapper.emitted('submit')![0]).toEqual(['my_company.example.com']);
    });

    it('does not show error display on valid submission', async () => {
      wrapper = mountComponent();

      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('example.com');
      await flushPromises();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      const errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(false);
    });

    it('clears previous error on valid submission', async () => {
      wrapper = mountComponent();

      // First trigger error with empty submission
      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      let errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(true);

      // Then submit valid domain
      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('example.com');
      await flushPromises();

      await form.trigger('submit.prevent');
      await flushPromises();

      errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // Back button
  // -------------------------------------------------------------------------

  describe('Back button', () => {
    it('emits back event when clicked', async () => {
      wrapper = mountComponent();

      const backButton = wrapper.find('[data-testid="domain-add-cancel-btn"]');
      await backButton.trigger('click');
      await flushPromises();

      expect(wrapper.emitted('back')).toBeTruthy();
    });

    it('has correct aria-label', () => {
      wrapper = mountComponent();

      const backButton = wrapper.find('[data-testid="domain-add-cancel-btn"]');
      expect(backButton.attributes('aria-label')).toBe('Go back to previous page');
    });

    it('is a button type button (not submit)', () => {
      wrapper = mountComponent();

      const backButton = wrapper.find('[data-testid="domain-add-cancel-btn"]');
      expect(backButton.attributes('type')).toBe('button');
    });
  });

  // -------------------------------------------------------------------------
  // Submit button loading state
  // -------------------------------------------------------------------------

  describe('Submit button loading state', () => {
    it('shows Continue text when not submitting', () => {
      wrapper = mountComponent({ isSubmitting: false });

      const submitButton = wrapper.find('[data-testid="domain-add-submit"]');
      expect(submitButton.text()).toContain('Continue');
      expect(submitButton.text()).not.toContain('Adding');
    });

    it('shows loading text when isSubmitting is true', () => {
      wrapper = mountComponent({ isSubmitting: true });

      const submitButton = wrapper.find('[data-testid="domain-add-submit"]');
      expect(submitButton.text()).toContain('Adding');
    });

    it('shows spinner when isSubmitting is true', () => {
      wrapper = mountComponent({ isSubmitting: true });

      const submitButton = wrapper.find('[data-testid="domain-add-submit"]');
      const spinner = submitButton.find('svg.animate-spin');
      expect(spinner.exists()).toBe(true);
    });

    it('does not show spinner when not submitting', () => {
      wrapper = mountComponent({ isSubmitting: false });

      const submitButton = wrapper.find('[data-testid="domain-add-submit"]');
      const spinner = submitButton.find('svg.animate-spin');
      expect(spinner.exists()).toBe(false);
    });

    it('is disabled when isSubmitting is true', () => {
      wrapper = mountComponent({ isSubmitting: true });

      const submitButton = wrapper.find('[data-testid="domain-add-submit"]');
      expect(submitButton.attributes('disabled')).toBeDefined();
    });

    it('is enabled when isSubmitting is false', () => {
      wrapper = mountComponent({ isSubmitting: false });

      const submitButton = wrapper.find('[data-testid="domain-add-submit"]');
      expect(submitButton.attributes('disabled')).toBeUndefined();
    });
  });

  // -------------------------------------------------------------------------
  // Error display
  // -------------------------------------------------------------------------

  describe('Error display', () => {
    it('shows ErrorDisplay when localError exists after empty submission', async () => {
      wrapper = mountComponent();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      const errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(true);
    });

    it('shows ErrorDisplay when localError exists after invalid domain', async () => {
      wrapper = mountComponent();

      const input = wrapper.find('[data-testid="domain-input-field"]');
      await input.setValue('ab');
      await flushPromises();

      const form = wrapper.find('[data-testid="domain-add-form"]');
      await form.trigger('submit.prevent');
      await flushPromises();

      const errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(true);
    });

    it('hides ErrorDisplay when no error', () => {
      wrapper = mountComponent();

      const errorDisplay = wrapper.find('[data-testid="error-display"]');
      expect(errorDisplay.exists()).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // Accessibility
  // -------------------------------------------------------------------------

  describe('Accessibility', () => {
    it('submit button has aria-live for status announcements', () => {
      wrapper = mountComponent();

      const submitButton = wrapper.find('[data-testid="domain-add-submit"]');
      expect(submitButton.attributes('aria-live')).toBe('polite');
    });

    it('form has submit type button', () => {
      wrapper = mountComponent();

      const submitButton = wrapper.find('[data-testid="domain-add-submit"]');
      expect(submitButton.attributes('type')).toBe('submit');
    });
  });
});
