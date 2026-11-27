// src/tests/composables/useSecretForm.spec.ts

/**
 * useSecretForm — the validation messages come from locale keys, with the
 * values the user needs passed as params.
 */

import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';

// Renders `key{json params}` so both the key and its params can be asserted.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string, params?: unknown) => (params ? `${key}${JSON.stringify(params)}` : key),
  }),
}));

import { useSecretForm } from '@/shared/composables/useSecretForm';

function setup(
  passphrase: Record<string, unknown>,
  policy: Record<string, unknown> = {},
  secretOptions: Record<string, unknown> = {}
) {
  const bootstrap = useBootstrapStore();
  bootstrap.$patch({
    authenticated: true,
    organization: { objid: 'a', extid: 'on-a', display_name: 'A', is_default: true },
    secret_options: { default_ttl: 3600, ttl_options: [60, 3600], passphrase, ...secretOptions },
  });
  const organizations = useOrganizationStore();
  organizations.setCurrentOrganization({
    ...organizations.currentOrganization!,
    sharing_policy: {
      passphrase_required: false,
      max_ttl: null,
      recipient_email_mode: 'unrestricted',
      recipient_email_domains: [],
      ...policy,
    },
  });
  const { form, validation, operations } = useSecretForm();
  operations.updateField('secret', 'content');
  return { form, validation, operations };
}

describe('useSecretForm validation messages', () => {
  beforeEach(() => {
    setActivePinia(createTestingPinia({ createSpy: vi.fn, stubActions: false }));
  });

  it('accepts a valid form', () => {
    const { validation } = setup({ minimum_length: 4, maximum_length: 12 });
    expect(validation.validate()).toBe(true);
    expect(validation.errors.size).toBe(0);
  });

  it('reports a missing required passphrase', () => {
    const { validation, operations } = setup(
      { minimum_length: 4, maximum_length: 12 },
      { passphrase_required: true }
    );
    operations.updateField('passphrase', '   ');

    expect(validation.validate()).toBe(false);
    expect(validation.errors.get('passphrase')).toBe('web.secrets.error_passphrase_required');
  });

  it('reports a passphrase below the minimum, with the minimum', () => {
    const { validation, operations } = setup({ minimum_length: 8, maximum_length: 12 });
    operations.updateField('passphrase', 'short');

    expect(validation.validate()).toBe(false);
    expect(validation.errors.get('passphrase')).toBe(
      'web.secrets.error_passphrase_too_short{"length":8}'
    );
  });

  it('reports a passphrase above the maximum, with the maximum', () => {
    const { validation, operations } = setup({ minimum_length: 4, maximum_length: 12 });
    operations.updateField('passphrase', 'x'.repeat(13));

    expect(validation.validate()).toBe(false);
    expect(validation.errors.get('passphrase')).toBe(
      'web.secrets.error_passphrase_too_long{"length":12}'
    );
  });

  it('reports the missing character classes by their keys, in order', () => {
    const { validation, operations } = setup({
      minimum_length: 4,
      maximum_length: 12,
      enforce_complexity: true,
    });
    operations.updateField('passphrase', 'abcdefgh');

    expect(validation.validate()).toBe(false);
    const missing = [
      'web.secrets.passphrase_class_uppercase',
      'web.secrets.passphrase_class_number',
      'web.secrets.passphrase_class_symbol',
    ].join(', ');
    expect(validation.errors.get('passphrase')).toBe(
      `web.secrets.error_passphrase_complexity${JSON.stringify({ missing })}`
    );
  });

  it('reports the first broken rule, length before complexity, when both fail', () => {
    const { validation, operations } = setup({
      minimum_length: 8,
      maximum_length: 12,
      enforce_complexity: true,
    });
    operations.updateField('passphrase', 'Ab1');

    validation.validate();
    expect(validation.errors.get('passphrase')).toBe(
      'web.secrets.error_passphrase_too_short{"length":8}'
    );
  });

  it('reports a recipient outside the allowed domains', () => {
    const { validation, operations } = setup(
      { minimum_length: 4, maximum_length: 12 },
      { recipient_email_mode: 'restricted', recipient_email_domains: ['example.com'] }
    );
    operations.updateField('recipient', 'person@other.example');

    expect(validation.validate()).toBe(false);
    expect(validation.errors.get('recipient')).toBe('web.secrets.error_recipient_restricted');
  });

  it('reports a lifetime ceiling below 60 seconds', () => {
    const { validation } = setup({ minimum_length: 4, maximum_length: 12 }, { max_ttl: 30 });

    expect(validation.validate()).toBe(false);
    expect(validation.errors.get('ttl')).toBe('web.secrets.error_ttl_below_minimum');
  });
});
