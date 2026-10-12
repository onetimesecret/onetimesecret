// src/tests/components/SecretContentInputArea.spec.ts
//
// The Markdown switch is opt-in: it shows only when the parent binds
// displayType, so forms whose endpoint takes no display_type (incoming
// secrets) never render a control that does nothing. On the homepage it sits
// below the textarea with a visible hint, like the passphrase field.

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

  it('sits below the textarea, before the preview', () => {
    const wrapper = mountInput({ displayType: SecretDisplayType.MARKDOWN });
    const order = wrapper
      .findAll('textarea, [data-testid="secret-markdown-toggle"], [data-testid="secret-markdown-preview"]')
      .map((el) => el.attributes('data-testid'));
    expect(order).toEqual([
      'secret-content-input',
      'secret-markdown-toggle',
      'secret-markdown-preview',
    ]);
  });

  it('is labelled and described by visible text, not a tooltip', () => {
    const wrapper = mountInput({ displayType: SecretDisplayType.TEXT });
    const toggle = wrapper.find(TOGGLE);
    const label = wrapper.find(`label[for="${toggle.attributes('id')}"]`);
    const hint = wrapper.find(`#${toggle.attributes('aria-describedby')}`);
    // The test i18n has no messages loaded, so text renders as its key
    expect(label.text()).toBe('web.secrets.markdown_mode_label');
    expect(hint.text()).toBe('web.secrets.markdown_mode_hint');
    expect(toggle.attributes('title')).toBeUndefined();
  });
});
