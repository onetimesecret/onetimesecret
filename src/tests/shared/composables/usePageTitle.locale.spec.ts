// src/tests/shared/composables/usePageTitle.locale.spec.ts
//
// usePageTitle and the active locale. A language switch changes no route, so
// the router does not set the title again; the composable re-applies the last
// title in the new language itself (document title, og:title and
// twitter:title). A title key the active locale lacks resolves through the
// fallback chain to English, not to the raw key.
//
// A separate file from usePageTitle.spec.ts because that spec mocks the
// composer with te() always false. Here '@/i18n' supplies a real vue-i18n
// composer with a fallback map shaped like the default config.

import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { effectScope, nextTick } from 'vue';

vi.mock('@/i18n', async () => {
  const { createI18n } = await import('vue-i18n');
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    fallbackLocale: { de_AT: ['de_AT', 'de', 'en'], default: ['en'] },
    missingWarn: false,
    fallbackWarn: false,
    // `never`, as createRealI18n in src/tests/setup.ts does: createI18n's
    // message typing does not accept this literal.
    messages: {
      en: { web: { TITLES: { dashboard: 'Dashboard', only_english: 'Only in English' } } },
      bg: { web: { TITLES: { dashboard: 'Табло' } } },
    } as never,
  });
  return { globalComposer: i18n.global };
});

import { globalComposer } from '@/i18n';
import { usePageTitle } from '@/shared/composables/usePageTitle';

const metaContent = (selector: string) => document.querySelector(selector)?.getAttribute('content');

async function switchTo(locale: string) {
  (globalComposer.locale as unknown as { value: string }).value = locale;
  await nextTick();
}

describe('usePageTitle and the active locale', () => {
  beforeEach(async () => {
    document.head.innerHTML =
      '<meta property="og:title" content=""><meta name="twitter:title" content="">';
    document.title = '';
    setActivePinia(
      createTestingPinia({
        createSpy: vi.fn,
        initialState: { bootstrap: { display_domain: 'secrets.example.com' } },
      })
    );
    await switchTo('en');
  });

  it('re-applies a title key in the new language, meta tags included', async () => {
    const { setTitle } = usePageTitle();
    setTitle('web.TITLES.dashboard');
    expect(document.title).toBe('Dashboard - secrets.example.com');

    await switchTo('bg');

    expect(document.title).toBe('Табло - secrets.example.com');
    expect(metaContent('meta[property="og:title"]')).toBe('Табло - secrets.example.com');
    expect(metaContent('meta[name="twitter:title"]')).toBe('Табло - secrets.example.com');
  });

  it('re-applies the last title set, whoever set it', async () => {
    usePageTitle().setTitle('web.TITLES.dashboard');
    usePageTitle().setTitle('Custom heading');

    await switchTo('bg');

    expect(document.title).toBe('Custom heading - secrets.example.com');
  });

  it('keeps a computed title in the new language', async () => {
    const scope = effectScope();
    scope.run(() => {
      usePageTitle().useComputedTitle(() => `${globalComposer.t('web.TITLES.dashboard')} #1`);
    });
    await nextTick();
    expect(document.title).toBe('Dashboard #1 - secrets.example.com');

    await switchTo('bg');

    expect(document.title).toBe('Табло #1 - secrets.example.com');
    scope.stop();
  });

  // The real fallback: bg has no only_english, so vue-i18n walks the chain
  // (default: [en]) for both the key check and the text.
  it('renders the English text for a key the active locale lacks', async () => {
    await switchTo('bg');
    expect(globalComposer.te('web.TITLES.only_english', 'bg')).toBe(false);

    usePageTitle().setTitle('web.TITLES.only_english');

    expect(document.title).toBe('Only in English - secrets.example.com');
  });

  it('keeps plain text that is not a key as it is', async () => {
    await switchTo('bg');

    expect(usePageTitle().formatTitle('web.TITLES.not_a_key')).toBe(
      'web.TITLES.not_a_key - secrets.example.com'
    );
  });
});
