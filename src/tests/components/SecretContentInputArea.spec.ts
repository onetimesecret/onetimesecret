// src/tests/components/SecretContentInputArea.spec.ts
//
// The Markdown toggle is opt-in: it shows only when the parent binds
// displayType, so forms whose endpoint takes no display_type (incoming
// secrets) never render a control that does nothing.

import SecretContentInputArea from '@/apps/secret/components/form/SecretContentInputArea.vue';
import { SecretDisplayType } from '@/schemas/contracts/secret';
import { createTestI18n } from '@tests/setup';
import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';

const TOGGLE = '[data-testid="secret-markdown-toggle"]';
const PREVIEW = '[data-testid="secret-markdown-preview"]';

function mountInput(props: Record<string, unknown> = {}) {
  return mount(SecretContentInputArea, {
    props,
    global: {
      plugins: [createTestI18n()],
      stubs: { OIcon: true, MarkdownRenderer: true },
    },
  });
}

describe('SecretContentInputArea Markdown toggle', () => {
  it('is hidden when displayType is not bound', () => {
    const wrapper = mountInput();
    expect(wrapper.find(TOGGLE).exists()).toBe(false);
    expect(wrapper.find(PREVIEW).exists()).toBe(false);
  });

  it('is shown when displayType is bound', () => {
    const wrapper = mountInput({ displayType: SecretDisplayType.TEXT });
    expect(wrapper.find(TOGGLE).exists()).toBe(true);
    expect(wrapper.find(TOGGLE).attributes('aria-checked')).toBe('false');
    expect(wrapper.find(PREVIEW).exists()).toBe(false);
  });

  it('shows the preview in markdown mode', () => {
    const wrapper = mountInput({ displayType: SecretDisplayType.MARKDOWN });
    expect(wrapper.find(TOGGLE).attributes('aria-checked')).toBe('true');
    expect(wrapper.find(PREVIEW).exists()).toBe(true);
  });

  it('emits the new display type when toggled', async () => {
    const wrapper = mountInput({ displayType: SecretDisplayType.TEXT });
    await wrapper.find(TOGGLE).trigger('click');
    expect(wrapper.emitted('update:displayType')).toEqual([[SecretDisplayType.MARKDOWN]]);
  });
});
