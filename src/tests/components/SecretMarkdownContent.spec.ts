// src/tests/components/SecretMarkdownContent.spec.ts
//
// Revealed markdown secrets: rendered by default, raw source on request, and
// the rendered output goes through the sanitizer.

import SecretMarkdownContent from '@/apps/secret/components/SecretMarkdownContent.vue';
import { createTestI18n } from '@tests/setup';
import { mount, type VueWrapper } from '@vue/test-utils';
import { describe, expect, it, vi } from 'vitest';

const RENDERED = '[data-testid="secret-content-markdown"]';
const SOURCE = '[data-testid="secret-content"]';

function mountContent(content: string, props: Record<string, unknown> = {}): VueWrapper {
  return mount(SecretMarkdownContent, {
    props: { content, contentId: 'secret-content-abc123', rows: 3, ...props },
    global: {
      plugins: [createTestI18n()],
      stubs: { OIcon: true },
    },
  });
}

// The renderer loads marked/highlight.js lazily, so the rendered markup
// appears a tick after mount.
async function waitForRendered(wrapper: VueWrapper) {
  await vi.waitFor(() => {
    expect(wrapper.find('[data-testid="markdown-rendered"]').exists()).toBe(true);
  });
}

describe('SecretMarkdownContent', () => {
  it('renders the markdown by default and does not show the source textarea', async () => {
    const wrapper = mountContent('# Hello\n\nSome **bold** text');
    await waitForRendered(wrapper);

    const rendered = wrapper.find(RENDERED);
    expect(rendered.exists()).toBe(true);
    expect(rendered.html()).toContain('<h1>Hello</h1>');
    expect(rendered.html()).toContain('<strong>bold</strong>');
    expect(wrapper.find(SOURCE).exists()).toBe(false);
    expect(
      wrapper.find('[data-testid="secret-markdown-view-rendered"]').attributes('aria-pressed')
    ).toBe('true');
  });

  it('switches to the raw source on request and back', async () => {
    const wrapper = mountContent('# Hello');

    await wrapper.find('[data-testid="secret-markdown-view-source"]').trigger('click');
    const textarea = wrapper.find(SOURCE);
    expect(textarea.exists()).toBe(true);
    expect((textarea.element as HTMLTextAreaElement).value).toBe('# Hello');
    expect(textarea.attributes('id')).toBe('secret-content-abc123');
    expect(textarea.attributes('readonly')).toBeDefined();
    expect(wrapper.find(RENDERED).exists()).toBe(false);

    await wrapper.find('[data-testid="secret-markdown-view-rendered"]').trigger('click');
    expect(wrapper.find(RENDERED).exists()).toBe(true);
    expect(wrapper.find(SOURCE).exists()).toBe(false);
  });

  it('sanitizes what it renders', async () => {
    const wrapper = mountContent(
      'hi <script>alert(1)</script> [x](javascript:alert(1)) <img src="https://evil.example/p.gif">'
    );
    await waitForRendered(wrapper);

    const html = wrapper.find(RENDERED).html();
    expect(html).not.toContain('<script');
    expect(html).not.toContain('<a');
    expect(html).not.toContain('href=');
    expect(html).not.toContain('<img');
    expect(html).toContain('hi');
  });

  it('points both views at the description the caller names', async () => {
    const wrapper = mountContent('# Hello', { describedBy: 'copy-instructions' });
    expect(wrapper.find(RENDERED).attributes('aria-describedby')).toBe('copy-instructions');

    await wrapper.find('[data-testid="secret-markdown-view-source"]').trigger('click');
    expect(wrapper.find(SOURCE).attributes('aria-describedby')).toBe('copy-instructions');
  });

  it('sets no aria-describedby when the caller names no description', async () => {
    const wrapper = mountContent('# Hello');
    expect(wrapper.find(RENDERED).attributes('aria-describedby')).toBeUndefined();

    await wrapper.find('[data-testid="secret-markdown-view-source"]').trigger('click');
    expect(wrapper.find(SOURCE).attributes('aria-describedby')).toBeUndefined();
  });
});
