// src/tests/components/SecretContentInputArea.spec.ts
//
// The input area renders the Markdown preview but no control: the parent
// owns display_type and its switch (SecretForm keeps it under Advanced
// Options). Forms whose endpoint takes no display_type (incoming secrets)
// leave it unbound and get a plain textarea.

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

describe('SecretContentInputArea Markdown preview', () => {
  it('renders no preview when displayType is not bound', () => {
    const wrapper = mountInput();
    expect(wrapper.find(PREVIEW).exists()).toBe(false);
  });

  it('renders no preview in text mode', () => {
    const wrapper = mountInput({ displayType: SecretDisplayType.TEXT });
    expect(wrapper.find(PREVIEW).exists()).toBe(false);
  });

  it('shows the preview below the textarea in markdown mode', () => {
    const wrapper = mountInput({ displayType: SecretDisplayType.MARKDOWN });
    const order = wrapper
      .findAll(`textarea, ${PREVIEW}`)
      .map((el) => el.attributes('data-testid'));
    expect(order).toEqual(['secret-content-input', 'secret-markdown-preview']);
  });

  it('renders no Markdown control of its own', () => {
    const wrapper = mountInput({ displayType: SecretDisplayType.MARKDOWN });
    expect(wrapper.find(TOGGLE).exists()).toBe(false);
  });
});
