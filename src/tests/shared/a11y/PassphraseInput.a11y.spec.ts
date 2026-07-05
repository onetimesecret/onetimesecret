// src/tests/shared/a11y/PassphraseInput.a11y.spec.ts

//
// Layer-1 accessibility regression tests for PassphraseInput.vue — the
// passphrase field used on secret-creation forms. It exposes a labelled
// <input> (sr-only label), show/hide + clear buttons with aria-labels, and an
// error message linked via aria-describedby / aria-invalid.
//
// HeadlessUI's Popover is mocked so the panel (and thus the input) is always
// rendered, letting axe inspect the field content directly.
//

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, vi, afterEach } from 'vitest';
import PassphraseInput from '@/apps/workspace/components/forms/privacy-options/PassphraseInput.vue';
import { createTestI18n } from '@tests/setup';
import { expectNoA11yViolations } from '@tests/support/axe';

vi.mock('@headlessui/vue', () => ({
  Popover: {
    name: 'Popover',
    template: '<div class="popover"><slot :open="true" /></div>',
    props: ['class'],
  },
  PopoverButton: {
    name: 'PopoverButton',
    template: '<button type="button" :disabled="disabled"><slot /></button>',
    props: ['disabled', 'class'],
  },
  PopoverPanel: {
    name: 'PopoverPanel',
    template: '<div class="popover-panel"><slot /></div>',
    props: ['class'],
  },
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" aria-hidden="true" />',
    props: ['collection', 'name', 'class'],
  },
}));

const i18n = createTestI18n();

describe('PassphraseInput a11y', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  const mountComponent = (props: Record<string, unknown> = {}) =>
    mount(PassphraseInput, {
      props: { modelValue: '', ...props },
      global: { plugins: [i18n] },
    });

  it('has no a11y violations with an empty passphrase', async () => {
    wrapper = mountComponent();
    await expectNoA11yViolations(wrapper);
  });

  it('has no a11y violations with a valid passphrase entered', async () => {
    wrapper = mountComponent({ modelValue: 'correct horse battery staple', minLength: 6 });
    await expectNoA11yViolations(wrapper);
  });

  it('has no a11y violations when showing a validation error', async () => {
    // Value shorter than minLength triggers the role="alert" error message.
    wrapper = mountComponent({ modelValue: 'ab', minLength: 8 });
    await expectNoA11yViolations(wrapper);
  });

  it('has no a11y violations when disabled', async () => {
    wrapper = mountComponent({ disabled: true });
    await expectNoA11yViolations(wrapper);
  });
});
