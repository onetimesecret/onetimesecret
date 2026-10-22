// src/tests/apps/secret/components/canonical/SecretConfirmationForm.spec.ts
//
// A failed reveal must say why, whether or not the secret has a passphrase.
// The error used to render only inside the passphrase section, so a refused
// reveal of a secret without one (every simple-mode verification secret,
// #4831) dropped back to the same button with no message, and the visitor
// kept clicking.

import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { describe, it, expect } from 'vitest';
import { createTestI18n } from '@tests/setup';
import SecretConfirmationForm from '@/apps/secret/components/canonical/SecretConfirmationForm.vue';

const i18n = createTestI18n();

const mountForm = (record: Record<string, unknown>, error: unknown) =>
  mount(SecretConfirmationForm, {
    props: {
      secretIdentifier: 'abc123',
      record: record as never,
      details: null,
      isSubmitting: false,
      error,
    },
    global: {
      plugins: [i18n, createTestingPinia()],
      stubs: { NeedHelpModal: true, SecretRecipientHelpContent: true },
    },
  });

const REFUSED = 'Cannot verify an account when you are already logged in';

describe('canonical SecretConfirmationForm error display', () => {
  it('shows the error for a secret without a passphrase', () => {
    const wrapper = mountForm({ has_passphrase: false, verification: true }, REFUSED);

    const errors = wrapper.findAll('[data-testid="secret-reveal-error"]');
    expect(errors).toHaveLength(1);
    expect(errors[0].text()).toBe(REFUSED);
    expect(errors[0].attributes('role')).toBe('alert');
  });

  it('shows the error once, under the field, for a passphrase-protected secret', () => {
    const wrapper = mountForm({ has_passphrase: true }, 'Incorrect passphrase');

    const errors = wrapper.findAll('[data-testid="secret-reveal-error"]');
    expect(errors).toHaveLength(1);
    expect(errors[0].attributes('id')).toBe('passphrase-error');
    expect(errors[0].text()).toBe('Incorrect passphrase');
  });

  it('shows no error before a reveal fails', () => {
    const wrapper = mountForm({ has_passphrase: false }, '');

    expect(wrapper.find('[data-testid="secret-reveal-error"]').exists()).toBe(false);
  });
});
