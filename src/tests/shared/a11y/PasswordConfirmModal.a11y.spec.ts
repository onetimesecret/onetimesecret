// src/tests/shared/a11y/PasswordConfirmModal.a11y.spec.ts

//
// Layer-1 accessibility regression tests for PasswordConfirmModal.vue — a
// password form field with an associated <label>, a visibility toggle button,
// and an error message linked via aria-describedby / aria-invalid.
//
// NOTE: HeadlessUI's Dialog is mocked (as in PasswordConfirmModal.spec.ts), so
// the modal's focus-trap/dialog-name is provided by HeadlessUI at runtime, not
// exercised here. These specs assert the FORM content is structurally
// accessible, which is what the component itself owns.
//

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, vi, afterEach } from 'vitest';
import PasswordConfirmModal from '@/shared/components/modals/PasswordConfirmModal.vue';
import { createTestI18n } from '@tests/setup';
import { expectNoA11yViolations } from '@tests/support/axe';

vi.mock('@headlessui/vue', () => ({
  Dialog: {
    name: 'Dialog',
    template: '<div role="dialog" aria-label="Confirm"><slot /></div>',
    props: ['class'],
    emits: ['close'],
  },
  DialogPanel: {
    name: 'DialogPanel',
    template: '<div class="dialog-panel"><slot /></div>',
    props: ['class'],
  },
  DialogTitle: {
    name: 'DialogTitle',
    template: '<h3><slot /></h3>',
    props: ['as', 'class'],
  },
  TransitionRoot: {
    name: 'TransitionRoot',
    template: '<div v-if="show"><slot /></div>',
    props: ['as', 'show'],
  },
  TransitionChild: {
    name: 'TransitionChild',
    template: '<div><slot /></div>',
    props: ['as', 'enter', 'enterFrom', 'enterTo', 'leave', 'leaveFrom', 'leaveTo'],
  },
}));

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" aria-hidden="true" />',
    props: ['collection', 'name', 'class', 'size'],
  },
}));

const i18n = createTestI18n();

describe('PasswordConfirmModal a11y', () => {
  let wrapper: VueWrapper;

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  const mountComponent = (props: Record<string, unknown> = {}) =>
    mount(PasswordConfirmModal, {
      props: { open: true, title: 'Confirm Action', ...props },
      global: { plugins: [i18n] },
    });

  it('has no a11y violations in the default (open) state', async () => {
    wrapper = mountComponent();
    await expectNoA11yViolations(wrapper);
  });

  it('has no a11y violations with a description', async () => {
    wrapper = mountComponent({ description: 'Please confirm your password to continue.' });
    await expectNoA11yViolations(wrapper);
  });

  it('has no a11y violations while displaying an error', async () => {
    wrapper = mountComponent({ error: 'Invalid password' });
    await expectNoA11yViolations(wrapper);
  });

  it('has no a11y violations in the loading state', async () => {
    wrapper = mountComponent({ loading: true });
    await expectNoA11yViolations(wrapper);
  });
});
