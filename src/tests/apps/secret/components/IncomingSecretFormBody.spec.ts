// src/tests/apps/secret/components/IncomingSecretFormBody.spec.ts

import { mount } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

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

const { defaultTtl } = vi.hoisted(() => ({
  defaultTtl: { value: null as number | null },
}));

vi.mock('@/shared/composables/useIncomingSecret', () => ({
  useIncomingSecret: () => ({
    form: ref({ recipientId: '', secret: '', memo: '', passphrase: '' }),
    errors: ref({}),
    isSubmitting: ref(false),
    memoMaxLength: ref(50),
    secretMaxLength: ref(1000),
    passphraseRequired: ref(false),
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
    const compound = `web.UNITS.ttl.duration_compound${JSON.stringify({
      head: `web.UNITS.ttl.duration${hour}`,
      tail: `web.UNITS.ttl.duration${twoSeconds}`,
    })}`;
    expect(wrapper.text()).toContain(
      `incoming.expires_after_duration${JSON.stringify({ duration: compound })}`
    );
  });
});
