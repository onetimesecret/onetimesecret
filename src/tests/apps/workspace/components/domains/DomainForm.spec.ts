// src/tests/apps/workspace/components/domains/DomainForm.spec.ts
//
// Tests for the "guided address cards" DomainForm.vue. The form drives its
// entire UX off analyzeDomain(raw) and keeps the original emit contract:
//   emit('submit', <finalHostnameString>)  and  emit('back').
//
// i18n runs in PASS-THROUGH mode (createTestI18n): missing keys render as the
// key itself, so these tests assert on data-testids, emitted values, and the
// presence/absence of blocks — never on translated copy.

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestI18n } from '@tests/setup';
import DomainForm from '@/apps/workspace/components/domains/DomainForm.vue';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

// A minimal stand-in for DomainInput: a bare <input> that mirrors v-model via
// update:modelValue. The parent binds :model-value / @update:model-value.
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
    props: ['modelValue', 'placeholder', 'isValid', 'describedby', 'autofocus', 'required'],
    emits: ['update:modelValue'],
  },
}));

// ---------------------------------------------------------------------------
// i18n setup
// ---------------------------------------------------------------------------

const i18n = createTestI18n();

// ---------------------------------------------------------------------------
// Helpers
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

  const mountComponent = (props: { isSubmitting?: boolean } = {}) =>
    mount(DomainForm, {
      props: {
        isSubmitting: props.isSubmitting ?? false,
      },
      global: {
        plugins: [i18n],
      },
    });

  // Type into the (mocked) domain field.
  const typeDomain = async (w: VueWrapper, value: string) => {
    const input = w.find('[data-testid="domain-input-field"]');
    await input.setValue(value);
    await flushPromises();
  };

  const submitForm = async (w: VueWrapper) => {
    const form = w.find('[data-testid="domain-add-form"]');
    await form.trigger('submit.prevent');
    await flushPromises();
  };

  // Pick a radio inside the apex chooser by its native value.
  const chooseAddress = async (w: VueWrapper, value: string) => {
    const radio = w.find(`input[type="radio"][value="${value}"]`);
    expect(radio.exists()).toBe(true);
    await radio.setValue();
    await flushPromises();
  };

  // -------------------------------------------------------------------------
  // Rendering
  // -------------------------------------------------------------------------

  describe('Form rendering', () => {
    it('renders the form element', () => {
      wrapper = mountComponent();
      expect(wrapper.find('[data-testid="domain-add-form"]').exists()).toBe(true);
    });

    it('renders the step rail', () => {
      wrapper = mountComponent();
      const rail = wrapper.find('nav');
      expect(rail.exists()).toBe(true);
      // Add / Verify / Brand steps are present in the rail.
      expect(rail.text()).toContain('web.domains.add.step_add');
      expect(rail.text()).toContain('web.domains.add.step_verify');
      expect(rail.text()).toContain('web.domains.add.step_brand');
    });

    it('renders the DomainInput field', () => {
      wrapper = mountComponent();
      expect(wrapper.find('[data-testid="domain-input-field"]').exists()).toBe(true);
    });

    it('renders back and submit buttons', () => {
      wrapper = mountComponent();
      expect(wrapper.find('[data-testid="domain-add-cancel-btn"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="domain-add-submit"]').exists()).toBe(true);
    });

    it('shows neither echo nor apex cards nor error initially', () => {
      wrapper = mountComponent();
      expect(wrapper.find('[data-testid="domain-echo"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="domain-apex-cards"]').exists()).toBe(false);
      expect(wrapper.find('[data-testid="domain-error"]').exists()).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // Empty submission
  // -------------------------------------------------------------------------

  describe('Empty submission', () => {
    it('shows an error and does not emit submit', async () => {
      wrapper = mountComponent();

      await submitForm(wrapper);

      expect(wrapper.find('[data-testid="domain-error"]').exists()).toBe(true);
      expect(wrapper.emitted('submit')).toBeFalsy();
    });

    it('treats whitespace-only input as empty', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, '   ');
      await submitForm(wrapper);

      expect(wrapper.find('[data-testid="domain-error"]').exists()).toBe(true);
      expect(wrapper.emitted('submit')).toBeFalsy();
    });
  });

  // -------------------------------------------------------------------------
  // Invalid hostnames
  // -------------------------------------------------------------------------

  describe('Invalid hostname', () => {
    it('malformed input shows the error block and does not emit', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, '-bad-');
      await submitForm(wrapper);

      expect(wrapper.find('[data-testid="domain-error"]').exists()).toBe(true);
      expect(wrapper.emitted('submit')).toBeFalsy();
    });

    it('unrecognized suffix shows the error block and does not emit', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, 'example.c');
      await submitForm(wrapper);

      expect(wrapper.find('[data-testid="domain-error"]').exists()).toBe(true);
      expect(wrapper.emitted('submit')).toBeFalsy();
    });

    it('clears the error once the input becomes valid again', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, '-bad-');
      await submitForm(wrapper);
      expect(wrapper.find('[data-testid="domain-error"]').exists()).toBe(true);

      // Editing resets attempted -> error disappears before the next submit.
      await typeDomain(wrapper, 'secrets.acme.com');
      expect(wrapper.find('[data-testid="domain-error"]').exists()).toBe(false);
    });
  });

  // -------------------------------------------------------------------------
  // Deeper hostname (echo path)
  // -------------------------------------------------------------------------

  describe('Subdomain (echo) path', () => {
    it('shows the echo block and no apex cards', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, 'secrets.acme.com');

      expect(wrapper.find('[data-testid="domain-echo"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="domain-apex-cards"]').exists()).toBe(false);
    });

    it('emits the hostname verbatim on submit', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, 'secrets.acme.com');
      await submitForm(wrapper);

      expect(wrapper.emitted('submit')).toBeTruthy();
      expect(wrapper.emitted('submit')![0]).toEqual(['secrets.acme.com']);
    });

    it('normalizes scheme/case/path before emitting', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, 'HTTPS://Links.Acme.COM/foo');
      await submitForm(wrapper);

      expect(wrapper.emitted('submit')![0]).toEqual(['links.acme.com']);
    });
  });

  // -------------------------------------------------------------------------
  // Apex (address cards) path
  // -------------------------------------------------------------------------

  describe('Apex (address cards) path', () => {
    it('shows the apex cards and no echo', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, 'acme.com');

      expect(wrapper.find('[data-testid="domain-apex-cards"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="domain-echo"]').exists()).toBe(false);
      // The four subdomain options plus the root option are rendered.
      expect(wrapper.find('[data-testid="domain-address-option-secrets"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="domain-address-option-links"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="domain-address-option-secure"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="domain-address-option-share"]').exists()).toBe(true);
      expect(wrapper.find('[data-testid="domain-root-option"]').exists()).toBe(true);
    });

    it('disables submit while no address is chosen', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, 'acme.com');

      const submit = wrapper.find('[data-testid="domain-add-submit"]');
      expect(submit.attributes('disabled')).toBeDefined();
    });

    it('does not emit when submitted without a choice', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, 'acme.com');
      await submitForm(wrapper);

      expect(wrapper.emitted('submit')).toBeFalsy();
    });

    it('emits "<sub>.<registrable>" after choosing a subdomain', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, 'acme.com');
      await chooseAddress(wrapper, 'secrets');

      // Choosing enables the submit button.
      expect(
        wrapper.find('[data-testid="domain-add-submit"]').attributes('disabled')
      ).toBeUndefined();

      await submitForm(wrapper);

      expect(wrapper.emitted('submit')![0]).toEqual(['secrets.acme.com']);
    });

    it('emits the bare registrable after choosing root', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, 'acme.com');
      await chooseAddress(wrapper, 'root');
      await submitForm(wrapper);

      expect(wrapper.emitted('submit')![0]).toEqual(['acme.com']);
    });

    it('handles multi-part suffixes when choosing a subdomain', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, 'acme.co.uk');
      await chooseAddress(wrapper, 'links');
      await submitForm(wrapper);

      expect(wrapper.emitted('submit')![0]).toEqual(['links.acme.co.uk']);
    });

    it('resets a pending choice when the input changes', async () => {
      wrapper = mountComponent();

      await typeDomain(wrapper, 'acme.com');
      await chooseAddress(wrapper, 'secrets');
      expect(
        wrapper.find('[data-testid="domain-add-submit"]').attributes('disabled')
      ).toBeUndefined();

      // Re-typing another apex clears the choice -> submit disabled again.
      await typeDomain(wrapper, 'other.com');
      expect(
        wrapper.find('[data-testid="domain-add-submit"]').attributes('disabled')
      ).toBeDefined();
    });
  });

  // -------------------------------------------------------------------------
  // Back button
  // -------------------------------------------------------------------------

  describe('Back button', () => {
    it('emits back when clicked', async () => {
      wrapper = mountComponent();

      await wrapper.find('[data-testid="domain-add-cancel-btn"]').trigger('click');

      expect(wrapper.emitted('back')).toBeTruthy();
    });

    it('is a type=button, not a submit', () => {
      wrapper = mountComponent();
      expect(
        wrapper.find('[data-testid="domain-add-cancel-btn"]').attributes('type')
      ).toBe('button');
    });
  });

  // -------------------------------------------------------------------------
  // Submitting state
  // -------------------------------------------------------------------------

  describe('Submitting state', () => {
    it('shows the spinner and disables submit while submitting', () => {
      wrapper = mountComponent({ isSubmitting: true });

      const submit = wrapper.find('[data-testid="domain-add-submit"]');
      expect(submit.find('svg.animate-spin').exists()).toBe(true);
      expect(submit.text()).toContain('web.COMMON.adding_ellipses');
      expect(submit.attributes('disabled')).toBeDefined();
    });

    it('has no spinner and is enabled when not submitting', () => {
      wrapper = mountComponent({ isSubmitting: false });

      const submit = wrapper.find('[data-testid="domain-add-submit"]');
      expect(submit.find('svg.animate-spin').exists()).toBe(false);
      expect(submit.attributes('disabled')).toBeUndefined();
    });
  });

  // -------------------------------------------------------------------------
  // Accessibility
  // -------------------------------------------------------------------------

  describe('Accessibility', () => {
    it('submit button has aria-live', () => {
      wrapper = mountComponent();
      expect(
        wrapper.find('[data-testid="domain-add-submit"]').attributes('aria-live')
      ).toBe('polite');
    });

    it('error block is a role=alert', async () => {
      wrapper = mountComponent();

      await submitForm(wrapper);

      const error = wrapper.find('[data-testid="domain-error"]');
      expect(error.attributes('role')).toBe('alert');
    });
  });
});
