// src/tests/shared/a11y/SplitButton.a11y.spec.ts

//
// Layer-1 accessibility regression tests for SplitButton.vue — the primary
// call-to-action button used to create/generate secret links on public pages.
//

import { mount, VueWrapper } from '@vue/test-utils';
import { describe, it, vi, afterEach, beforeEach } from 'vitest';
import { ref, nextTick } from 'vue';
import SplitButton from '@/shared/components/ui/SplitButton.vue';
import { expectNoA11yViolations } from '@tests/support/axe';

// Track the magic keys mock state (mirrors SplitButton.spec.ts conventions).
const mockMetaEnter = ref(false);
const mockControlEnter = ref(false);

vi.mock('@vueuse/core', () => ({
  useMagicKeys: vi.fn(() => ({
    'Meta+Enter': mockMetaEnter,
    'Control+Enter': mockControlEnter,
  })),
  whenever: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: vi.fn(() => ({
    t: vi.fn((key: string) => {
      const translations: Record<string, string> = {
        'web.LABELS.create_link_short': 'Create Link',
        'web.COMMON.button_generate_secret_short': 'Generate',
      };
      return translations[key] || key;
    }),
  })),
}));

describe('SplitButton a11y', () => {
  let wrapper: VueWrapper;

  beforeEach(() => {
    mockMetaEnter.value = false;
    mockControlEnter.value = false;
  });

  afterEach(() => {
    if (wrapper) wrapper.unmount();
  });

  const mountComponent = (props: Record<string, unknown> = {}) =>
    mount(SplitButton, {
      props: {
        content: 'some secret content',
        withGenerate: false,
        disabled: false,
        disableGenerate: false,
        cornerClass: 'rounded-xl',
        primaryColor: '#3b82f6',
        buttonTextLight: true,
        keyboardShortcutEnabled: false,
        showKeyboardHint: false,
        ...props,
      },
    });

  it('has no a11y violations in the default state', async () => {
    wrapper = mountComponent();
    await expectNoA11yViolations(wrapper);
  });

  it('has no a11y violations when disabled', async () => {
    wrapper = mountComponent({ disabled: true });
    await expectNoA11yViolations(wrapper);
  });

  it('has no a11y violations when showing the keyboard hint', async () => {
    wrapper = mountComponent({ showKeyboardHint: true, keyboardShortcutEnabled: true });
    await expectNoA11yViolations(wrapper);
  });

  it('has no a11y violations with the actions dropdown open', async () => {
    wrapper = mountComponent({ withGenerate: true });
    const toggle = wrapper.find('button[aria-label="Show more actions"]');
    await toggle.trigger('click');
    await nextTick();
    await expectNoA11yViolations(wrapper);
  });
});
