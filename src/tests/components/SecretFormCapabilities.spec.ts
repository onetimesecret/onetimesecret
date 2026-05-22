// src/tests/components/SecretFormCapabilities.spec.ts

import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import SecretForm from '@/apps/secret/components/form/SecretForm.vue';

vi.mock('@/shared/composables/useDomainContext', () => ({
  useDomainContext: vi.fn(() => ({
    currentContext: { value: { domain: '', displayName: '', isCanonical: true } },
    isContextActive: { value: false },
    hasMultipleContexts: { value: false },
    availableDomains: { value: [] },
    setContext: vi.fn(),
    resetContext: vi.fn(),
  })),
}));

vi.mock('@/shared/composables/useSecretConcealer', () => ({
  useSecretConcealer: vi.fn(() => ({
    form: { secret: '', passphrase: '', ttl: 300, share_domain: '', recipient: '' },
    validation: { errors: new Map() },
    operations: { updateField: vi.fn(), reset: vi.fn() },
    isSubmitting: false,
    submit: vi.fn(),
  })),
}));

vi.mock('@/shared/composables/usePrivacyOptions', () => ({
  usePrivacyOptions: vi.fn(() => ({
    state: { passphraseVisibility: false },
    lifetimeOptions: [{ label: '5 minutes', value: 300 }],
    updatePassphrase: vi.fn(),
    updateTtl: vi.fn(),
    updateRecipient: vi.fn(),
    togglePassphraseVisibility: vi.fn(),
  })),
}));

vi.mock('vue-router', () => ({
  useRouter: vi.fn(() => ({ push: vi.fn() })),
}));

vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => key),
  })),
}));

const RECIPIENT_TESTID = '[data-testid="secret-recipient-input"]';

const mountForm = (
  withRecipient: boolean,
  recipientCapability: boolean | undefined
) => {
  const capabilities =
    recipientCapability === undefined ? {} : { recipient: recipientCapability };
  return mount(SecretForm, {
    props: { enabled: true, withRecipient },
    global: {
      plugins: [
        createTestingPinia({
          createSpy: vi.fn,
          initialState: {
            bootstrap: {
              ui: { capabilities },
              secret_options: {
                passphrase: { required: false, minimum_length: 8, enforce_complexity: false },
              },
            },
          },
        }),
      ],
    },
  });
};

describe('SecretForm - recipient capability gating', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('hides the recipient field when ui.capabilities.recipient is false', () => {
    const wrapper = mountForm(true, false);
    expect(wrapper.find(RECIPIENT_TESTID).exists()).toBe(false);
  });

  it('shows the recipient field when ui.capabilities.recipient is true', () => {
    const wrapper = mountForm(true, true);
    expect(wrapper.find(RECIPIENT_TESTID).exists()).toBe(true);
  });

  it('shows the recipient field when the capability flag is unset (default enabled)', () => {
    const wrapper = mountForm(true, undefined);
    expect(wrapper.find(RECIPIENT_TESTID).exists()).toBe(true);
  });

  it('keeps the recipient field hidden when withRecipient is false regardless of capability', () => {
    const wrapper = mountForm(false, true);
    expect(wrapper.find(RECIPIENT_TESTID).exists()).toBe(false);
  });
});
