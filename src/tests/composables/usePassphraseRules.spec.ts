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

  it('is the last broken rule, the order the form has always reported in', () => {
    const complex = { ...config, enforce_complexity: true };
    expect(reportedPassphraseIssue('abc', { required: false, config: complex })).toEqual({
      code: 'complexity',
      missing: ['uppercase', 'number', 'symbol'],
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
    expect(rules.errorText.value).toBe('web.secrets.passphraseMaximumLength{"length":10}');

    value.value = 'x'.repeat(10);
    expect(rules.errorText.value).toBe('');
  });

  it('reports complexity with the complexity key, and offers it as a hint', () => {
    setup({ minimum_length: 4, maximum_length: 64, enforce_complexity: true });
    const rules = usePassphraseRules(() => 'abcdefgh');

    expect(rules.complexityEnforced.value).toBe(true);
    expect(rules.complexityHint.value).toBe('web.secrets.passphraseComplexityRequired');
    expect(rules.errorText.value).toBe('web.secrets.passphraseComplexityRequired');
  });

  it('has no complexity hint when complexity is not enforced', () => {
    setup({ minimum_length: 4, maximum_length: 64 });
    expect(usePassphraseRules(() => '').complexityHint.value).toBe('');
  });

  it('lets a minimum length above zero override the published one', () => {
    setup({ minimum_length: 4, maximum_length: 64 });
    expect(usePassphraseRules(() => '', () => 9).minLength.value).toBe(9);
    expect(usePassphraseRules(() => '', () => 0).minLength.value).toBe(4);
  });

  it('holds back the required error until the field has been interacted with', () => {
    setup({ minimum_length: 4, maximum_length: 64, required: true });
    const rules = usePassphraseRules(() => '');

    expect(rules.passphraseRequired.value).toBe(true);
    expect(rules.errorText.value).toBe('');

    rules.markInteracted();
    expect(rules.issue.value).toEqual({ code: 'required' });
    expect(rules.errorText.value).toBe('web.secrets.passphraseRequired');
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
});
