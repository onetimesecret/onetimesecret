// src/tests/i18n.spec.ts
//
// src/i18n.ts: English bundled, every other locale a lazy chunk loaded on
// demand, and a locale activated in a composer only once its messages, and
// those of its fallback chain, are registered there.
//
// Each test imports a fresh copy of the module (vi.resetModules), because the
// loader cache and the global instance are module state, and the fallback map
// is read from the bootstrap payload when the module loads. Real files from
// generated/locales/ (globalSetup runs locales:sync) stand in for the chunks;
// vi.doMock on one file's path makes that "chunk" fail.

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { readdirSync } from 'fs';
import { resolve } from 'path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { watch } from 'vue';

type I18nModule = typeof import('@/i18n');

const LOCALES_DIR = resolve(process.cwd(), 'generated/locales');
const localeFile = (code: string) => resolve(LOCALES_DIR, `${code}.json`);

/**
 * The fallback map as the default config writes it (etc/defaults/
 * config.defaults.yaml, internationalization.fallback_locale): BCP 47 keys,
 * underscored values.
 */
const DEFAULT_FALLBACK = {
  de: ['de', 'de_AT', 'en'],
  'de-AT': ['de_AT', 'de', 'en'],
  'fr-CA': ['fr_CA', 'fr_FR', 'en'],
  'pt-BR': ['pt_BR', 'pt_PT', 'en'],
  'pt-PT': ['pt_PT', 'pt_BR', 'en'],
  default: ['en'],
};

/** Imports a fresh src/i18n.ts that reads `fallback` from the bootstrap payload. */
async function loadI18n(fallback: unknown = DEFAULT_FALLBACK): Promise<I18nModule> {
  vi.resetModules();
  window.__BOOTSTRAP_ME__ = {
    ...window.__BOOTSTRAP_ME__,
    fallback_locale: fallback,
  } as BootstrapPayload;
  return import('@/i18n');
}

/**
 * Makes the "chunk" for one locale fail to import, for modules imported after
 * this. vitest reports the factory's error as the `cause` of its own, so tests
 * match `cause.message`.
 */
function failChunk(code: string) {
  mockedFiles.add(code);
  vi.doMock(localeFile(code), () => {
    throw new Error(`chunk ${code} failed`);
  });
}

const mockedFiles = new Set<string>();

afterEach(() => {
  for (const code of mockedFiles) vi.doUnmock(localeFile(code));
  mockedFiles.clear();
  document.documentElement.removeAttribute('lang');
});

const sorted = (locales: readonly string[]) => [...locales].sort();

describe('src/i18n.ts', () => {
  // globalSetup runs locales:sync, so generated/locales/ is populated here.
  const generatedLocales = readdirSync(LOCALES_DIR)
    .filter((name) => name.endsWith('.json'))
    .map((name) => name.replace(/\.json$/, ''))
    .sort();

  describe('loadLocaleMessages', () => {
    it('finds generated locale files to compare against', () => {
      expect(generatedLocales).toContain('en');
      expect(generatedLocales.length).toBeGreaterThan(1);
    });

    // The glob patterns are relative to src/i18n.ts. A root-anchored pattern
    // matched nothing under vitest, so every locale would be missing.
    it('loads every generated locale', async () => {
      const { loadLocaleMessages } = await loadI18n();

      const loaded = await Promise.all(
        generatedLocales.map(async (code) => [code, await loadLocaleMessages(code)] as const)
      );

      for (const [code, messages] of loaded) {
        expect(Object.keys(messages), code).not.toHaveLength(0);
      }
    });

    it('shares one load between concurrent and later calls', async () => {
      const { loadLocaleMessages } = await loadI18n();

      const first = loadLocaleMessages('ja');
      expect(loadLocaleMessages('ja')).toBe(first);
      const messages = await first;
      expect(await loadLocaleMessages('ja')).toBe(messages);
    });

    it('resolves English from the bundled messages', async () => {
      const { loadLocaleMessages } = await loadI18n();

      const messages = await loadLocaleMessages('en');

      expect(messages).toHaveProperty('web');
    });

    it('rejects a locale with no generated file, including Object.prototype names', async () => {
      const { loadLocaleMessages } = await loadI18n();

      for (const code of ['xx', 'zh_Hant_TW', 'constructor', '__proto__', 'toString']) {
        await expect(loadLocaleMessages(code), code).rejects.toThrow(
          `No messages exist for locale "${code}"`
        );
      }
    });

    // The language store asks this before offering a locale the server lists
    // (languageStore.ts, loadSupportedLocales).
    it('reports which locales have messages, without loading any', async () => {
      const { hasLocaleMessages } = await loadI18n();

      for (const code of generatedLocales) expect(hasLocaleMessages(code), code).toBe(true);
      for (const code of ['xx', 'zh_Hant_TW', 'constructor', '__proto__', 'toString']) {
        expect(hasLocaleMessages(code), code).toBe(false);
      }
    });

    it('rejects a chunk that fails, then retries on the next call', async () => {
      failChunk('ko');
      const { loadLocaleMessages } = await loadI18n();

      await expect(loadLocaleMessages('ko')).rejects.toHaveProperty(
        'cause.message',
        'chunk ko failed'
      );

      vi.doUnmock(localeFile('ko'));
      await expect(loadLocaleMessages('ko')).resolves.toHaveProperty('web');
    });

    // vite:preloadError with preventDefault() resolves the import with
    // undefined; the entries' handler does that when it reloads the page.
    it('rejects a module that resolves without messages', async () => {
      mockedFiles.add('tr');
      vi.doMock(localeFile('tr'), () => ({ default: undefined }));
      const { loadLocaleMessages } = await loadI18n();

      await expect(loadLocaleMessages('tr')).rejects.toThrow(
        'Messages for locale "tr" did not load'
      );
    });
  });

  describe('createI18nInstance().setLocale', () => {
    it('starts on English with only English registered', async () => {
      const { createI18nInstance } = await loadI18n();

      const { composer } = createI18nInstance();

      expect(composer.locale.value).toBe('en');
      expect(composer.availableLocales).toEqual(['en']);
      expect(composer.t('web.LABELS.loading')).toBe('Loading...');
    });

    it('loads and registers a locale, then activates it', async () => {
      const { createI18nInstance } = await loadI18n();
      const { composer, setLocale } = createI18nInstance();

      await expect(setLocale('ja')).resolves.toBe(true);

      expect(composer.locale.value).toBe('ja');
      expect(composer.t('web.LABELS.loading')).toBe('読み込み中...');
      expect(composer.t('web.LABELS.loading', {}, { locale: 'en' })).toBe('Loading...');
    });

    it('registers the messages before the locale changes', async () => {
      const { createI18nInstance } = await loadI18n();
      const { composer, setLocale } = createI18nInstance();
      const seenAtSwitch: string[][] = [];
      // flush: 'sync' runs inside the assignment to composer.locale, so it sees
      // exactly what the first render in the new locale would see.
      watch(composer.locale, () => seenAtSwitch.push([...composer.availableLocales].sort()), {
        flush: 'sync',
      });

      await setLocale('de');

      expect(seenAtSwitch).toEqual([['de', 'de_AT', 'en']]);
    });

    it.each([
      ['de', ['de', 'de_AT', 'en']],
      ['de_AT', ['de', 'de_AT', 'en']],
      ['fr_CA', ['en', 'fr_CA', 'fr_FR']],
      ['pt_BR', ['en', 'pt_BR', 'pt_PT']],
      ['pt_PT', ['en', 'pt_BR', 'pt_PT']],
      ['bg', ['bg', 'en']],
    ])('loads the fallback chain the default config gives %s', async (code, expected) => {
      const { createI18nInstance } = await loadI18n();
      const { composer, setLocale } = createI18nInstance();

      await setLocale(code);

      expect(sorted(composer.availableLocales)).toEqual(expected);
    });

    it('does not rewrite the bootstrap fallback map it normalizes', async () => {
      await loadI18n();
      const { getBootstrapValue } = await import('@/services/bootstrap.service');

      expect(Object.keys(getBootstrapValue('fallback_locale') as object)).toContain('de-AT');
    });

    it('loads only English behind a locale when the fallback config is a single locale', async () => {
      const { createI18nInstance } = await loadI18n('en');
      const { composer, setLocale } = createI18nInstance();

      await setLocale('de_AT');

      expect(sorted(composer.availableLocales)).toEqual(['de_AT', 'en']);
    });

    it('fails the switch when a locale in the chain fails, registering nothing', async () => {
      failChunk('de');
      const { createI18nInstance } = await loadI18n();
      const { composer, setLocale } = createI18nInstance();
      await setLocale('nl');

      await expect(setLocale('de_AT')).rejects.toHaveProperty('cause.message', 'chunk de failed');

      expect(composer.locale.value).toBe('nl');
      expect(sorted(composer.availableLocales)).toEqual(['en', 'nl']);
    });

    it('keeps the previous locale when the load fails, and can retry', async () => {
      failChunk('ko');
      const { createI18nInstance } = await loadI18n();
      const { composer, setLocale } = createI18nInstance();
      await setLocale('nl');

      await expect(setLocale('ko')).rejects.toHaveProperty('cause.message', 'chunk ko failed');
      expect(composer.locale.value).toBe('nl');
      expect(composer.availableLocales).not.toContain('ko');

      vi.doUnmock(localeFile('ko'));
      await expect(setLocale('ko')).resolves.toBe(true);
      expect(composer.locale.value).toBe('ko');
    });

    it('rejects a locale with no messages and keeps the previous one', async () => {
      const { createI18nInstance } = await loadI18n();
      const { composer, setLocale } = createI18nInstance();

      await expect(setLocale('xx')).rejects.toThrow('No messages exist for locale "xx"');

      expect(composer.locale.value).toBe('en');
    });

    it('resolves false for a call a newer one supersedes; the newer locale stays', async () => {
      const { createI18nInstance } = await loadI18n();
      const { composer, setLocale } = createI18nInstance();

      const older = setLocale('ru');
      const newer = setLocale('nl');

      expect(await Promise.all([older, newer])).toEqual([false, true]);
      expect(composer.locale.value).toBe('nl');
      expect(composer.availableLocales).not.toContain('ru');
    });

    it('lets a newer English switch win over an older load still in flight', async () => {
      const { createI18nInstance } = await loadI18n();
      const { composer, setLocale } = createI18nInstance();

      const older = setLocale('pl');
      const newer = setLocale('en');

      expect(await Promise.all([older, newer])).toEqual([false, true]);
      expect(composer.locale.value).toBe('en');
    });

    it('resolves false for a superseded call whose own load failed', async () => {
      failChunk('ko');
      const { createI18nInstance } = await loadI18n();
      const { composer, setLocale } = createI18nInstance();

      const older = setLocale('ko');
      const newer = setLocale('nl');

      expect(await Promise.all([older, newer])).toEqual([false, true]);
      expect(composer.locale.value).toBe('nl');
    });

    it('registers messages per instance', async () => {
      const { createI18nInstance } = await loadI18n();
      const first = createI18nInstance();
      const second = createI18nInstance();

      await first.setLocale('ja');

      expect(second.composer.locale.value).toBe('en');
      expect(second.composer.availableLocales).toEqual(['en']);

      await second.setLocale('ja');
      expect(second.composer.t('web.LABELS.loading')).toBe('読み込み中...');
    });

    it('does not share registrations through the global instance', async () => {
      const { createI18nInstance, globalComposer, setGlobalLocale } = await loadI18n();

      await setGlobalLocale('bg');
      const preview = createI18nInstance();

      expect(globalComposer.locale.value).toBe('bg');
      expect(preview.composer.locale.value).toBe('en');
      expect(preview.composer.availableLocales).toEqual(['en']);
    });
  });

  describe('<html lang>', () => {
    it('converts locale codes to BCP 47 tags', async () => {
      const { toLanguageTag } = await loadI18n();

      expect(toLanguageTag('pt_BR')).toBe('pt-BR');
      expect(toLanguageTag('de_AT')).toBe('de-AT');
      expect(toLanguageTag('bg')).toBe('bg');
    });

    it('follows the global instance on activation', async () => {
      const { setGlobalLocale } = await loadI18n();
      document.documentElement.lang = 'en';

      await setGlobalLocale('pt_BR');

      expect(document.documentElement.lang).toBe('pt-BR');
    });

    it('is not touched by a preview instance', async () => {
      const { createI18nInstance } = await loadI18n();
      document.documentElement.lang = 'en';

      await createI18nInstance().setLocale('bg');

      expect(document.documentElement.lang).toBe('en');
    });

    it('stays put for a superseded or failed global switch', async () => {
      failChunk('ko');
      const { globalComposer, setGlobalLocale } = await loadI18n();
      document.documentElement.lang = 'en';

      const older = setGlobalLocale('pt_BR');
      const newer = setGlobalLocale('de_AT');
      expect(await Promise.all([older, newer])).toEqual([false, true]);
      expect(document.documentElement.lang).toBe('de-AT');

      await expect(setGlobalLocale('ko')).rejects.toHaveProperty(
        'cause.message',
        'chunk ko failed'
      );
      expect(document.documentElement.lang).toBe('de-AT');
      expect(globalComposer.locale.value).toBe('de_AT');
    });
  });
});
