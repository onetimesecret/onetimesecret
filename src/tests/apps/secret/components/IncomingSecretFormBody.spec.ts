// src/tests/apps/secret/components/IncomingSecretFormBody.spec.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { createTestingPinia } from '@pinia/testing';
import { mount } from '@vue/test-utils';
import { setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { nextTick, ref } from 'vue';

// Renders `key{json params}` so the duration handed to the expiry line is
// visible; a plural call renders `key#n`.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string, arg?: unknown) => {
      if (typeof arg === 'number') return `${key}#${arg}`;
      return arg ? `${key}${JSON.stringify(arg)}` : key;
    },
  }),
}));

const { defaultTtl, passphraseRequired } = vi.hoisted(() => ({
  defaultTtl: { value: null as number | null },
  passphraseRequired: { value: false },
}));

vi.mock('@/shared/composables/useIncomingSecret', () => ({
  useIncomingSecret: () => ({
    form: ref({ recipientId: '', secret: '', memo: '', passphrase: '' }),
    errors: ref({}),
    isSubmitting: ref(false),
    memoMaxLength: ref(50),
    secretMaxLength: ref(1000),
    passphraseRequired: ref(passphraseRequired.value),
    // Read at mount: each test sets the value before mounting.
    defaultTtl: ref(defaultTtl.value),
    recipients: ref([]),
    isFormValid: ref(true),
    validateMemo: vi.fn(),
    validateSecret: vi.fn(),
    validateRecipient: vi.fn(),
    submit: vi.fn(),
    resetForm: vi.fn(),
  }),
}));
vi.mock('@/shared/composables/useUnsavedInputGuard', () => ({ useUnsavedInputGuard: vi.fn() }));

vi.mock('@/apps/secret/components/incoming/IncomingMemoInput.vue', () => ({
  default: { name: 'IncomingMemoInput', template: '<div />' },
}));
vi.mock('@/apps/secret/components/incoming/IncomingRecipientDropdown.vue', () => ({
  default: { name: 'IncomingRecipientDropdown', template: '<div />' },
}));
vi.mock('@/apps/secret/components/form/SecretContentInputArea.vue', () => ({
  default: { name: 'SecretContentInputArea', template: '<div />' },
}));

import IncomingSecretFormBody from '@/apps/secret/components/incoming/IncomingSecretFormBody.vue';

const hour = '{"count":1,"unit":"web.UNITS.ttl.time.hour#1"}';
const twoSeconds = '{"count":2,"unit":"web.UNITS.ttl.time.second#2"}';

beforeEach(() => {
  setActivePinia(createTestingPinia({ createSpy: vi.fn, stubActions: false }));
  defaultTtl.value = null;
  passphraseRequired.value = false;
});

describe('IncomingSecretFormBody expiry line', () => {
  it('is absent when the config has no default lifetime', () => {
    defaultTtl.value = null;
    const wrapper = mount(IncomingSecretFormBody);
    expect(wrapper.text()).not.toContain('incoming.expires_after_duration');
  });

  it('shows a whole number of hours as a formatted duration, not raw seconds', () => {
    defaultTtl.value = 3600;
    const wrapper = mount(IncomingSecretFormBody);
    expect(wrapper.text()).toContain(
      `incoming.expires_after_duration${JSON.stringify({ duration: `web.UNITS.ttl.duration${hour}` })}`
    );
    expect(wrapper.text()).not.toContain('incoming.expires_after_seconds');
  });

  it('shows a lifetime that is not a whole unit as an exact compound', () => {
    defaultTtl.value = 3602;
    const wrapper = mount(IncomingSecretFormBody);
    // The mock has no locale, so the parts are joined with the English list
    // pattern.
    const compound = `web.UNITS.ttl.duration${hour}, web.UNITS.ttl.duration${twoSeconds}`;
    expect(wrapper.text()).toContain(
      `incoming.expires_after_duration${JSON.stringify({ duration: compound })}`
    );
  });
});

describe('IncomingSecretFormBody passphrase rules', () => {
  const rules = { minimum_length: 8, enforce_complexity: true };

  function mountRequired() {
    passphraseRequired.value = true;
    useBootstrapStore().$patch({
      secret_options: { default_ttl: 3600, ttl_options: [3600], passphrase: rules },
    } as never);
    return mount(IncomingSecretFormBody);
  }

  it('shows the minimum length and complexity hints for a required passphrase', () => {
    const wrapper = mountRequired();
    expect(wrapper.find('[data-testid="incoming-passphrase-min-hint"]').text()).toContain(
      'web.secrets.passphraseMinimumLengthRequired'
    );
    expect(wrapper.find('[data-testid="incoming-passphrase-complexity-hint"]').exists()).toBe(true);
  });

  it('reports a too-short passphrase as the user types', async () => {
    const wrapper = mountRequired();
    const input = wrapper.find('[data-testid="incoming-passphrase-input"]');
    await input.setValue('short');
    await nextTick();
    expect(wrapper.find('[data-testid="incoming-passphrase-error"]').text()).toContain(
      'web.secrets.error_passphrase_too_short'
    );
    expect(input.attributes('aria-invalid')).toBe('true');
  });

  it('does not flag the empty required passphrase before the user touches it', () => {
    const wrapper = mountRequired();
    expect(wrapper.find('[data-testid="incoming-passphrase-error"]').exists()).toBe(false);
  });
});
