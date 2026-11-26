// src/tests/apps/workspace/components/forms/PassphraseChipValidation.spec.ts

/**
 * The dashboard passphrase chip (PassphraseInput), the mobile privacy sheet
 * (PrivacyOptionsSheet) and the mobile pill (PrivacyOptionsBar) validate with
 * the rules the form enforces on submit: minimum and maximum length,
 * complexity, and required.
 */

import { createTestingPinia } from '@pinia/testing';
import { mount, type VueWrapper } from '@vue/test-utils';
import { setActivePinia } from 'pinia';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { computed, ref } from 'vue';

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';

// Renders `key{json params}` so both the key and its params can be asserted.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string, params?: unknown) => (params ? `${key}${JSON.stringify(params)}` : key),
  }),
}));

// Render popover and dialog content unconditionally.
vi.mock('@headlessui/vue', () => {
  const slot = (name: string, tag = 'div') => ({
    name,
    inheritAttrs: false,
    template: `<${tag}><slot :open="true" /></${tag}>`,
  });
  return {
    Popover: slot('Popover'),
    PopoverButton: { ...slot('PopoverButton', 'button'), inheritAttrs: true },
    PopoverPanel: slot('PopoverPanel'),
    Dialog: slot('Dialog'),
    DialogPanel: slot('DialogPanel'),
    DialogTitle: slot('DialogTitle', 'h2'),
    TransitionChild: slot('TransitionChild'),
    TransitionRoot: slot('TransitionRoot'),
  };
});

vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span class="o-icon" :data-name="name" />', props: ['name'] },
}));

vi.mock('@/shared/composables/usePrivacyOptions', () => ({
  usePrivacyOptions: () => ({
    formatDuration: (seconds: number) => `${seconds}s`,
    lifetimeOptions: computed(() => [{ value: 3600, label: '3600s' }]),
    state: ref({ passphraseVisibility: false, lifetimeOptions: [] }),
  }),
}));

const isMobile = ref(true);
vi.mock('@vueuse/core', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@vueuse/core')>()),
  useMediaQuery: () => isMobile,
}));

import PrivacyOptionsBar from '@/apps/workspace/components/forms/PrivacyOptionsBar.vue';
import PassphraseInput from '@/apps/workspace/components/forms/privacy-options/PassphraseInput.vue';
import PrivacyOptionsSheet from '@/apps/workspace/components/forms/privacy-options/PrivacyOptionsSheet.vue';

type Rules = { minimum_length?: number; maximum_length?: number; enforce_complexity?: boolean; required?: boolean };

let wrapper: VueWrapper;

function pinia(passphrase: Rules) {
  const instance = createTestingPinia({ createSpy: vi.fn, stubActions: false });
  setActivePinia(instance);
  useBootstrapStore().$patch({
    secret_options: { default_ttl: 3600, ttl_options: [3600], passphrase },
  });
  return instance;
}

const MIN = 'web.secrets.passphraseMinimumLength{"length":6}';
const MIN_REQUIRED = 'web.secrets.passphraseMinimumLengthRequired{"length":6}';
const MAX = 'web.secrets.passphraseMaximumLength{"length":10}';
const COMPLEXITY = 'web.secrets.passphraseComplexityRequired';
const REQUIRED = 'web.secrets.passphraseRequired';

afterEach(() => wrapper?.unmount());

describe('PassphraseInput (desktop chip)', () => {
  const mountChip = (modelValue: string, rules: Rules, props: Record<string, unknown> = {}) => {
    wrapper = mount(PassphraseInput, {
      props: { modelValue, ...props },
      global: { plugins: [pinia(rules)] },
    });
  };
  const error = () => wrapper.find('[data-testid="passphrase-error"]');
  const hint = () => wrapper.find('[data-testid="passphrase-hint"]');
  const input = () => wrapper.get('#passphrase-input');

  it('reports a passphrase longer than the maximum, which it used to show as valid', () => {
    mountChip('x'.repeat(11), { minimum_length: 6, maximum_length: 10 });

    expect(error().text()).toBe(MAX);
    expect(input().attributes('aria-invalid')).toBe('true');
    expect(input().attributes('aria-describedby')).toBe('passphrase-error');
    expect(wrapper.get('button').classes()).toContain('bg-red-50');
  });

  it('reports a passphrase that lacks the enforced character classes', () => {
    mountChip('abcdefgh', { minimum_length: 6, maximum_length: 10, enforce_complexity: true });
    expect(error().text()).toBe(COMPLEXITY);
  });

  it('accepts a passphrase that meets every rule', () => {
    mountChip('Abcdef1!', { minimum_length: 6, maximum_length: 10, enforce_complexity: true });

    expect(error().exists()).toBe(false);
    expect(input().attributes('aria-invalid')).toBe('false');
    expect(wrapper.get('button').classes()).toContain('bg-brand-50');
  });

  it('still reports a passphrase shorter than the minimum', () => {
    mountChip('abc', { minimum_length: 6, maximum_length: 10 });
    expect(error().exists()).toBe(true);
  });

  it('uses the minLength prop over the published minimum when above zero', () => {
    mountChip('abcdefg', { minimum_length: 6, maximum_length: 64 }, { minLength: 8 });
    expect(error().exists()).toBe(true);
  });

  it('shows the complexity hint beside the minimum length hint when enforced', () => {
    mountChip('', { minimum_length: 6, maximum_length: 10, enforce_complexity: true });

    expect(hint().text()).toContain(MIN);
    expect(hint().text()).toContain(COMPLEXITY);
  });

  it('shows no complexity hint when complexity is not enforced', () => {
    mountChip('', { minimum_length: 6, maximum_length: 10 });

    expect(hint().text()).toContain(MIN);
    expect(hint().text()).not.toContain(COMPLEXITY);
  });

  it('shows a required passphrase as an error once left empty after interaction', async () => {
    mountChip('', { minimum_length: 6, maximum_length: 10, required: true });

    // Untouched: the neutral hint, no error.
    expect(error().exists()).toBe(false);
    expect(hint().text()).toContain(MIN_REQUIRED);
    expect(wrapper.get('button').classes()).toContain('bg-gray-50');

    await input().trigger('blur');

    expect(error().text()).toBe(REQUIRED);
    expect(input().attributes('aria-invalid')).toBe('true');
    expect(wrapper.get('button').classes()).toContain('bg-red-50');
  });

  it('never shows an empty optional passphrase as an error', async () => {
    mountChip('', { minimum_length: 6, maximum_length: 10 });
    await input().trigger('blur');
    expect(error().exists()).toBe(false);
  });
});

describe('PrivacyOptionsSheet (mobile sheet)', () => {
  const mountSheet = (currentPassphrase: string, rules: Rules) => {
    wrapper = mount(PrivacyOptionsSheet, {
      props: { modelValue: true, currentTtl: 3600, currentPassphrase },
      global: { plugins: [pinia(rules)] },
    });
  };
  const error = () => wrapper.find('[data-testid="sheet-passphrase-error"]');
  const hint = () => wrapper.find('[data-testid="sheet-passphrase-hint"]');
  const input = () => wrapper.get('#sheet-passphrase-input');

  it('reports a passphrase longer than the maximum', () => {
    mountSheet('x'.repeat(11), { minimum_length: 6, maximum_length: 10 });

    expect(error().text()).toBe(MAX);
    expect(input().attributes('aria-invalid')).toBe('true');
    expect(input().attributes('aria-describedby')).toBe('sheet-passphrase-error');
  });

  it('reports a passphrase that lacks the enforced character classes', () => {
    mountSheet('abcdefgh', { minimum_length: 6, maximum_length: 10, enforce_complexity: true });
    expect(error().text()).toBe(COMPLEXITY);
  });

  it('shows the complexity hint when enforced', () => {
    mountSheet('', { minimum_length: 6, maximum_length: 10, enforce_complexity: true });

    expect(hint().text()).toContain(MIN);
    expect(hint().text()).toContain(COMPLEXITY);
  });

  it('shows a required passphrase as an error once left empty after interaction', async () => {
    mountSheet('', { minimum_length: 6, maximum_length: 10, required: true });
    expect(error().exists()).toBe(false);

    await input().trigger('blur');
    expect(error().text()).toBe(REQUIRED);
  });
});

describe('PrivacyOptionsBar (mobile pill)', () => {
  const mountBar = (rules: Rules) => {
    isMobile.value = true;
    wrapper = mount(PrivacyOptionsBar, {
      props: { currentTtl: 3600, currentPassphrase: '' },
      global: {
        plugins: [pinia(rules)],
        stubs: { PrivacyOptionsSheet: true },
      },
    });
  };
  const marker = () => wrapper.find('[data-testid="privacy-options-required-marker"]');

  it('marks the pill as required when a passphrase is required', () => {
    mountBar({ minimum_length: 6, maximum_length: 10, required: true });

    expect(marker().exists()).toBe(true);
    expect(marker().text()).toContain('*');
    expect(marker().find('.sr-only').text()).toBe(REQUIRED);
  });

  it('has no marker when a passphrase is optional', () => {
    mountBar({ minimum_length: 6, maximum_length: 10 });
    expect(marker().exists()).toBe(false);
  });
});
