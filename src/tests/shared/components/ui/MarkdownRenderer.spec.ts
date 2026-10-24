// src/tests/shared/components/ui/MarkdownRenderer.spec.ts
//
// The parser is its own chunk, imported on first render. A load that fails
// must leave the source up as plain text and be forgotten, so that the next
// render fetches the chunk again. A chunk import fails in two ways: the
// import rejects, or it resolves without the module (Vite's preload helper
// resolves with undefined once vite:preloadError was default-prevented, see
// src/utils/preloadError.ts). The second is modelled here by a module without
// the renderer export.

import MarkdownRenderer from '@/shared/components/ui/MarkdownRenderer.vue';
import { captureAppLogs, type AppLogs } from '@/tests/utils/appLogs';
import { mount, type VueWrapper } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

/** The chunk the component imports on first render. Mocked per test with vi.doMock. */
const CHUNK = '@/shared/utils/markdown';

// The chunk import settles over several turns of the event loop in vitest, so
// each outcome is awaited rather than flushed. The real module (markdown-it,
// highlight.js, DOMPurify) can take more than vi.waitFor's default second to
// evaluate when the suite runs many files at once; the wait returns as soon as
// the outcome is on screen, so a long limit costs nothing in the normal case.
const SETTLE_MS = 15_000;
// Each test waits for the chunk at most twice; its own limit must cover that.
const TEST_MS = 2 * SETTLE_MS + 5_000;

const renderedHtml = (wrapper: VueWrapper) =>
  vi.waitFor(
    () => {
      const rendered = wrapper.find('[data-testid="markdown-rendered"]');
      expect(rendered.exists()).toBe(true);
      return rendered.html();
    },
    { timeout: SETTLE_MS }
  );

const fallbackText = (wrapper: VueWrapper) =>
  vi.waitFor(
    () => {
      const fallback = wrapper.find('[data-testid="markdown-fallback"]');
      expect(fallback.exists()).toBe(true);
      return fallback.text();
    },
    { timeout: SETTLE_MS }
  );

describe('MarkdownRenderer', () => {
  let logs: AppLogs;

  beforeEach(() => {
    logs = captureAppLogs();
  });

  afterEach(() => {
    vi.doUnmock(CHUNK);
  });

  it('renders once the chunk has loaded', async () => {
    const wrapper = mount(MarkdownRenderer, { props: { source: 'hello' } });

    expect(await renderedHtml(wrapper)).toContain('<p>hello</p>');
    expect(logs.error).not.toHaveBeenCalled();
  }, TEST_MS);

  it.each([
    [
      'rejects',
      () => {
        throw new Error('chunk failed');
      },
    ],
    ['resolves without the renderer', () => ({})],
  ])(
    'shows the source as plain text when the chunk import %s, and fetches again on the next render',
    async (_, outcome: () => Record<string, unknown>) => {
      vi.doMock(CHUNK, outcome);
      const wrapper = mount(MarkdownRenderer, { props: { source: 'first' } });

      expect(await fallbackText(wrapper)).toBe('first');
      expect(logs.error).toHaveBeenCalledTimes(1);

      // The chunk is reachable again: the next render has to import it anew
      // rather than reuse the failed load.
      vi.doUnmock(CHUNK);
      await wrapper.setProps({ source: 'second' });

      expect(await renderedHtml(wrapper)).toContain('<p>second</p>');
    },
    TEST_MS
  );
});
