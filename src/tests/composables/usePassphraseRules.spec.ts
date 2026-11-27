// src/tests/composables/usePassphraseRules.spec.ts

/**
 * usePassphraseRules — the one definition of the client's passphrase rules,
 * shared by the secret form's submit validation and the dashboard passphrase
 * chip and mobile sheet.
 */

import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';

// Renders `key{json params}` so both the key and its params can be asserted.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string, params?: unknown) => (params ? `${key}${JSON.stringify(params)}` : key),
  }),
}));

import { useSecretForm } from '@/shared/composables/useSecretForm';
import {
  passphraseIssues,
  reportedPassphraseIssue,
  usePassphraseRules,
} from '@/shared/composables/usePassphraseRules';

const config = { minimum_length: 8, maximum_length: 12, enforce_complexity: false };

describe('passphraseIssues', () => {
  it('accepts an empty optional passphrase', () => {
    expect(passphraseIssues('', { required: false, config })).toEqual([]);
  });

  it.each(['', '   '])('reports required for %j when a passphrase is required', (value) => {
    expect(passphraseIssues(value, { required: true, config })).toEqual([{ code: 'required' }]);
  });

  it('reports a value shorter than the minimum', () => {
    expect(passphraseIssues('short', { required: false, config })).toEqual([
      { code: 'too_short', length: 8 },
    ]);
  });

  it('reports a value longer than the maximum', () => {
    expect(passphraseIssues('x'.repeat(13), { required: false, config })).toEqual([
      { code: 'too_long', length: 12 },
    ]);
  });

  it('accepts a value at either bound', () => {
    expect(passphraseIssues('x'.repeat(8), { required: true, config })).toEqual([]);
    expect(passphraseIssues('x'.repeat(12), { required: true, config })).toEqual([]);
  });

  it('reports the character classes a value lacks when complexity is enforced', () => {
    const complex = { ...config, enforce_complexity: true };
    expect(passphraseIssues('abcdefgh', { required: false, config: complex })).toEqual([
      { code: 'complexity', missing: ['uppercase', 'number', 'symbol'] },
    ]);
    expect(passphraseIssues('Abcdef1!', { required: false, config: complex })).toEqual([]);
  });

  it('does not check complexity unless it is enforced', () => {
    expect(passphraseIssues('abcdefgh', { required: false, config })).toEqual([]);
  });

  it('skips limits that are unset or zero', () => {
    const unset = { minimum_length: 0, maximum_length: 0 };
    expect(passphraseIssues('a', { required: false, config: unset })).toEqual([]);
  });

  it('checks nothing but required when no rules are published', () => {
    expect(passphraseIssues('a', { required: false, config: undefined })).toEqual([]);
    expect(passphraseIssues('', { required: true, config: undefined })).toEqual([
      { code: 'required' },
    ]);
  });

  it('lists every broken rule in rule order', () => {
    const complex = { ...config, enforce_complexity: true };
    expect(passphraseIssues('abc', { required: false, config: complex })).toEqual([
      { code: 'too_short', length: 8 },
      { code: 'complexity', missing: ['uppercase', 'number', 'symbol'] },
    ]);
  });
});

describe('reportedPassphraseIssue', () => {
  it('is null for a valid value', () => {
    expect(reportedPassphraseIssue('x'.repeat(8), { required: true, config })).toBeNull();
  });

  it('is the first broken rule, in rule order', () => {
    const complex = { ...config, enforce_complexity: true };
    expect(reportedPassphraseIssue('abc', { required: false, config: complex })).toEqual({
      code: 'too_short',
      length: 8,
    });
  });
});

describe('usePassphraseRules', () => {
  const setup = (passphrase: Record<string, unknown>) => {
    const bootstrap = useBootstrapStore();
    bootstrap.$patch({ secret_options: { default_ttl: 3600, ttl_options: [3600], passphrase } });
  };

  beforeEach(() => {
    setActivePinia(createTestingPinia({ createSpy: vi.fn, stubActions: false }));
  });

  it('reads the published rules and reports the maximum length', () => {
    setup({ minimum_length: 4, maximum_length: 10 });
    const value = ref('x'.repeat(11));
    const rules = usePassphraseRules(() => value.value);

    expect(rules.minLength.value).toBe(4);
    expect(rules.issue.value).toEqual({ code: 'too_long', length: 10 });
    expect(rules.errorText.value).toBe('web.secrets.error_passphrase_too_long{"length":10}');

    value.value = 'x'.repeat(10);
    expect(rules.errorText.value).toBe('');
  });

  it('names the missing character classes in the error, and offers the rule as a hint', () => {
    setup({ minimum_length: 4, maximum_length: 64, enforce_complexity: true });
    const rules = usePassphraseRules(() => 'abcdefgh');

    expect(rules.complexityEnforced.value).toBe(true);
    expect(rules.complexityHint.value).toBe('web.secrets.passphraseComplexityRequired');
    const missing = [
      'web.secrets.passphrase_class_uppercase',
      'web.secrets.passphrase_class_number',
      'web.secrets.passphrase_class_symbol',
    ].join(', ');
    expect(rules.errorText.value).toBe(
      `web.secrets.error_passphrase_complexity${JSON.stringify({ missing })}`
    );
  });

  it('words a too-short error without "(Optional)", even when optional', () => {
    setup({ minimum_length: 6, maximum_length: 64 });
    const rules = usePassphraseRules(() => 'abc');

    // web.secrets.passphraseMinimumLength is the text that ends "(Optional)".
    expect(rules.passphraseRequired.value).toBe(false);
    expect(rules.errorText.value).toBe('web.secrets.error_passphrase_too_short{"length":6}');
    expect(rules.minimumLengthHint.value).toBe('web.secrets.passphraseMinimumLength{"length":6}');
  });

  it('has no complexity hint when complexity is not enforced', () => {
    setup({ minimum_length: 4, maximum_length: 64 });
    expect(usePassphraseRules(() => '').complexityHint.value).toBe('');
  });

  it('holds back the required error until the field has been interacted with', () => {
    setup({ minimum_length: 4, maximum_length: 64, required: true });
    const rules = usePassphraseRules(() => '');

    expect(rules.passphraseRequired.value).toBe(true);
    expect(rules.errorText.value).toBe('');

    rules.markInteracted();
    expect(rules.issue.value).toEqual({ code: 'required' });
    expect(rules.errorText.value).toBe('web.secrets.error_passphrase_required');
  });

  it('never reports an empty optional passphrase, interacted with or not', () => {
    setup({ minimum_length: 4, maximum_length: 64 });
    const rules = usePassphraseRules(() => '');
    rules.markInteracted();
    expect(rules.errorText.value).toBe('');
  });

  it.each([
    [true, 'web.secrets.passphraseMinimumLengthRequired{"length":4}'],
    [false, 'web.secrets.passphraseMinimumLength{"length":4}'],
  ])('words the minimum length hint for required=%s', (required, hint) => {
    setup({ minimum_length: 4, maximum_length: 64, required });
    expect(usePassphraseRules(() => '').minimumLengthHint.value).toBe(hint);
  });

  // The chip must accept exactly what submit accepts.
  it.each([
    ['', false],
    ['', true],
    ['   ', true],
    ['Ab1!', false],
    ['Ab1!Ab1!Ab1!x', false],
    ['abcdefgh', false],
    ['Abcdef1!', false],
    ['Abcdef1!', true],
  ])('agrees with submit validation for %j (required=%s)', (input, required) => {
    setup({ minimum_length: 8, maximum_length: 12, enforce_complexity: true, required });
    const rules = usePassphraseRules(() => input);
    rules.markInteracted();
    const { form, validation } = useSecretForm();
    form.secret = 'content';
    form.passphrase = input;
    validation.validate();

    expect(rules.issue.value === null).toBe(!validation.errors.has('passphrase'));
    expect(rules.errorText.value).toBe(validation.errors.get('passphrase') ?? '');
  });
});
