// src/tests/components/SecretFormAdvancedOptions.spec.ts
//
// The homepage form keeps the Markdown switch under a collapsed Advanced
// Options disclosure below the passphrase and expiration fields. While
// collapsed, Markdown mode shows as a chip beside the toggle so a non-default
// setting is never hidden.

import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
import SplitButton from '@/shared/components/ui/SplitButton.vue';
import { SecretDisplayType } from '@/schemas/contracts/secret';
import { reactive } from 'vue';

// Reactive so the switch and the chip follow display_type. The mock factory
// reads these lazily (at mount), after the module has initialised them.
const blankForm = () => ({
  secret: '',
  passphrase: '',
  ttl: 300,
  share_domain: '',
  recipient: '',
  display_type: SecretDisplayType.TEXT as SecretDisplayType,
});
let mockForm = reactive(blankForm());
const mockUpdateField = vi.fn((field: string, value: unknown) => {
  (mockForm as Record<string, unknown>)[field] = value;
});

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
    form: mockForm,
    validation: { errors: new Map() },
    operations: { updateField: mockUpdateField, reset: vi.fn() },
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

const ADVANCED_TOGGLE = '[data-testid="secret-advanced-options-toggle"]';
const ADVANCED_PANEL = '[data-testid="secret-advanced-options"]';
const ADVANCED_SUMMARY = '[data-testid="secret-advanced-options-summary"]';
const MARKDOWN_SWITCH = '[data-testid="secret-markdown-toggle"]';

const mountForm = () =>
  mount(SecretForm, {
    props: { enabled: true },
    global: {
      plugins: [
        createTestingPinia({
          createSpy: vi.fn,
          initialState: {
            bootstrap: {
              secret_options: {
                passphrase: { required: false, minimum_length: 8, enforce_complexity: false },
              },
            },
          },
        }),
      ],
      stubs: { MarkdownPreview: true },
    },
  });

describe('SecretForm Advanced Options', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockForm = reactive(blankForm());
  });

  it('starts collapsed, with the Markdown switch hidden', () => {
    const wrapper = mountForm();
    const toggle = wrapper.find(ADVANCED_TOGGLE);
    const panel = wrapper.find(ADVANCED_PANEL);

    expect(toggle.attributes('aria-expanded')).toBe('false');
    expect(toggle.attributes('aria-controls')).toBe(panel.attributes('id'));
    expect(toggle.text()).toContain('web.secrets.advanced_options');
    expect(panel.isVisible()).toBe(false);
  });

  it('sits below the passphrase and expiration fields', () => {
    const wrapper = mountForm();
    const order = wrapper
      .findAll(
        '[data-testid="secret-passphrase-input"], [data-testid="secret-ttl-select"], ' +
          ADVANCED_TOGGLE
      )
      .map((el) => el.attributes('data-testid'));
    expect(order).toEqual([
      'secret-passphrase-input',
      'secret-ttl-select',
      'secret-advanced-options-toggle',
    ]);
  });

  it('expands to show the Markdown switch, off by default', async () => {
    const wrapper = mountForm();
    await wrapper.find(ADVANCED_TOGGLE).trigger('click');

    expect(wrapper.find(ADVANCED_TOGGLE).attributes('aria-expanded')).toBe('true');
    expect(wrapper.find(ADVANCED_PANEL).isVisible()).toBe(true);
    expect(wrapper.find(MARKDOWN_SWITCH).attributes('aria-checked')).toBe('false');
  });

  it('sets display_type from the switch', async () => {
    const wrapper = mountForm();
    await wrapper.find(ADVANCED_TOGGLE).trigger('click');
    await wrapper.find(MARKDOWN_SWITCH).trigger('click');

    expect(mockUpdateField).toHaveBeenCalledWith('display_type', SecretDisplayType.MARKDOWN);
    expect(wrapper.find(MARKDOWN_SWITCH).attributes('aria-checked')).toBe('true');
  });

  it('shows Markdown mode beside the toggle while collapsed', async () => {
    const wrapper = mountForm();
    expect(wrapper.find(ADVANCED_SUMMARY).exists()).toBe(false);

    await wrapper.find(ADVANCED_TOGGLE).trigger('click');
    await wrapper.find(MARKDOWN_SWITCH).trigger('click');
    // Open: the switch itself shows the state
    expect(wrapper.find(ADVANCED_SUMMARY).exists()).toBe(false);

    await wrapper.find(ADVANCED_TOGGLE).trigger('click');
    expect(wrapper.find(ADVANCED_SUMMARY).text()).toBe('web.secrets.markdown_mode');
  });

  it('is hidden in generate-password mode, which sends no display_type', async () => {
    const wrapper = mountForm();
    await wrapper.findComponent(SplitButton).vm.$emit('update:action', 'generate-password');
    expect(wrapper.find(ADVANCED_TOGGLE).exists()).toBe(false);
  });
});
