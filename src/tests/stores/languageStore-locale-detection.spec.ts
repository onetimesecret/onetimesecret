// src/tests/stores/languageStore-locale-detection.spec.ts
//
// Tests for browser language detection and locale resolution in languageStore.
// Covers issue #2668: Browser language detection fails for regional locale variants.
//
// These tests assert CORRECT behavior. Failing tests document bugs that need fixing:
//
// Bug A: validateAndNormalizeLocale() is called in init() before supportedLocales
//   is populated by loadSupportedLocales(), so it cannot match/normalize the input
//   against actual supported locales. The input passes through unchanged (e.g.,
//   'it-IT' stays 'it-IT' instead of normalizing to 'it_IT').
//
// Bug B: initializeLocale() uses deviceLocale.value.split('-')[0] to extract the
//   primary language code, but the full deviceLocale value ('it-IT') is never
//   normalized to the underscore format ('it_IT') used by the supported_locales
//   list. So neither the primary code check ('it' not in list) nor the exact
//   check ('it-IT' !== 'it_IT') succeeds.

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { DEFAULT_LOCALE, useLanguageStore } from '@/shared/stores/languageStore';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { setupTestPinia } from '../setup';

describe('Language Store - Browser Locale Detection (#2668)', () => {
  let axiosMock: AxiosMockAdapter | null;
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  // Realistic supported locales matching the server's 30 locales
  const fullSupportedLocales = [
    'ar', 'bg', 'ca_ES', 'cs', 'da_DK', 'de', 'de_AT', 'el_GR',
    'en', 'eo', 'es', 'fr_CA', 'fr_FR', 'he', 'hu', 'it_IT',
    'ja', 'ko', 'mi_NZ', 'nl', 'pl', 'pt_BR', 'pt_PT', 'ru',
    'sl_SI', 'sv_SE', 'tr', 'uk', 'vi', 'zh',
  ];

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;

    vi.useFakeTimers();

    const sessionStorageMock = {
      getItem: vi.fn().mockReturnValue(null),
      setItem: vi.fn(),
      clear: vi.fn(),
    };
    Object.defineProperty(window, 'sessionStorage', { value: sessionStorageMock });

    bootstrapStore = useBootstrapStore();
    bootstrapStore.update({
      supported_locales: fullSupportedLocales,
    });
  });

  afterEach(() => {
    if (axiosMock) axiosMock.reset();
    vi.restoreAllMocks();
    vi.useRealTimers();
    vi.unstubAllGlobals();
    bootstrapStore.$reset();
  });

  // ---------------------------------------------------------------
  // Bug: init() with regional deviceLocale (e.g., 'it-IT') should
  // resolve to the underscore variant in supported_locales ('it_IT').
  // Currently fails because validateAndNormalizeLocale runs before
  // supportedLocales is populated, and initializeLocale does not
  // normalize hyphen to underscore.
  // ---------------------------------------------------------------
  describe('init() with deviceLocale for regional variants', () => {
    it('resolves deviceLocale "it-IT" to currentLocale "it_IT"', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'it-IT' });
      expect(store.currentLocale).toBe('it_IT');
    });

    it('resolves deviceLocale "fr-FR" to currentLocale "fr_FR"', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'fr-FR' });
      expect(store.currentLocale).toBe('fr_FR');
    });

    it('resolves deviceLocale "pt-BR" to currentLocale "pt_BR"', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'pt-BR' });
      expect(store.currentLocale).toBe('pt_BR');
    });

    it('resolves deviceLocale "de-AT" to currentLocale "de_AT"', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'de-AT' });
      expect(store.currentLocale).toBe('de_AT');
    });

    it('resolves deviceLocale "sv-SE" to currentLocale "sv_SE"', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'sv-SE' });
      expect(store.currentLocale).toBe('sv_SE');
    });

    it('resolves deviceLocale "el-GR" to currentLocale "el_GR"', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'el-GR' });
      expect(store.currentLocale).toBe('el_GR');
    });
  });

  // ---------------------------------------------------------------
  // Bug: init() with a primary-only code like 'it' should match the
  // regional variant 'it_IT'. Currently fails because
  // validateAndNormalizeLocale cannot find matches without
  // supportedLocales, and initializeLocale has no fallback logic
  // for primary-to-regional matching.
  // ---------------------------------------------------------------
  describe('init() with primary-only deviceLocale falling back to regional variant', () => {
    it('resolves deviceLocale "fr" to first matching fr variant', () => {
      // "fr" is not in supported_locales, but fr_CA and fr_FR are.
      const store = useLanguageStore();
      store.init({ deviceLocale: 'fr' });
      expect(['fr_CA', 'fr_FR']).toContain(store.currentLocale);
    });

    it('resolves deviceLocale "it" to "it_IT" (only it variant)', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'it' });
      expect(store.currentLocale).toBe('it_IT');
    });

    it('resolves deviceLocale "pt" to first matching pt variant', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'pt' });
      expect(['pt_BR', 'pt_PT']).toContain(store.currentLocale);
    });

    it('resolves deviceLocale "sv" to "sv_SE"', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'sv' });
      expect(store.currentLocale).toBe('sv_SE');
    });

    it('resolves deviceLocale "da" to "da_DK"', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'da' });
      expect(store.currentLocale).toBe('da_DK');
    });
  });

  // ---------------------------------------------------------------
  // These pass with the current implementation because simple locale
  // codes like 'de', 'ja', 'es' are directly in supported_locales.
  // The initializeLocale split('-')[0] on e.g. 'de' returns 'de',
  // which matches.
  // ---------------------------------------------------------------
  describe('init() with simple locale codes', () => {
    it('resolves deviceLocale "de" directly when "de" is in supported list', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'de' });
      expect(store.currentLocale).toBe('de');
    });

    it('resolves deviceLocale "ja" directly', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'ja' });
      expect(store.currentLocale).toBe('ja');
    });

    it('resolves deviceLocale "es" directly', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'es' });
      expect(store.currentLocale).toBe('es');
    });

    it('resolves deviceLocale "en" directly', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'en' });
      expect(store.currentLocale).toBe('en');
    });
  });

  describe('init() without deviceLocale falls back to DEFAULT_LOCALE', () => {
    it('uses DEFAULT_LOCALE when no deviceLocale provided', () => {
      const store = useLanguageStore();
      store.init();
      expect(store.currentLocale).toBe(DEFAULT_LOCALE);
    });

    it('uses DEFAULT_LOCALE when deviceLocale is undefined', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: undefined });
      expect(store.currentLocale).toBe(DEFAULT_LOCALE);
    });
  });

  describe('locale priority: user preference > session storage > deviceLocale', () => {
    it('user preference takes priority over deviceLocale', () => {
      bootstrapStore.update({
        supported_locales: fullSupportedLocales,
        cust: { locale: 'ja' },
      });

      const store = useLanguageStore();
      store.init({ deviceLocale: 'it-IT' });
      expect(store.currentLocale).toBe('ja');
    });

    it('session storage takes priority over deviceLocale', () => {
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue('es');

      const store = useLanguageStore();
      store.init({ deviceLocale: 'fr-FR' });
      expect(store.currentLocale).toBe('es');
    });

    it('deviceLocale is used when no user preference and no session storage', () => {
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue(null);

      const store = useLanguageStore();
      store.init({ deviceLocale: 'it-IT' });
      // Bug: currently resolves to 'en' because of the normalization timing issue
      expect(store.currentLocale).toBe('it_IT');
    });

    it('session storage with unsupported locale falls through to deviceLocale', () => {
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue('xx_YY');

      // When deviceLocale is 'de-AT' and both 'de' and 'de_AT' exist in supported
      // locales, the exact regional match 'de_AT' should be preferred over
      // the primary code 'de'.
      const store = useLanguageStore();
      store.init({ deviceLocale: 'de-AT' });
      expect(store.currentLocale).toBe('de_AT');
    });
  });

  // ---------------------------------------------------------------
  // These tests verify validateAndNormalizeLocale when called via
  // setCurrentLocale, where supportedLocales is already populated.
  // They pass because the normalization function works correctly
  // when it has the supported locales list to match against.
  // ---------------------------------------------------------------
  describe('validateAndNormalizeLocale via setCurrentLocale', () => {
    let store: ReturnType<typeof useLanguageStore>;

    beforeEach(() => {
      store = useLanguageStore();
      store.supportedLocales = fullSupportedLocales;
    });

    it('converts hyphen to underscore (it-IT -> it_IT)', () => {
      store.setCurrentLocale('it-IT');
      expect(store.currentLocale).toBe('it_IT');
    });

    it('handles case insensitivity (IT-it -> it_IT)', () => {
      store.setCurrentLocale('IT-it');
      expect(store.currentLocale).toBe('it_IT');
    });

    it('handles uppercase with underscore (FR_FR -> fr_FR)', () => {
      store.setCurrentLocale('FR_FR');
      expect(store.currentLocale).toBe('fr_FR');
    });

    it('handles mixed case with hyphen (Pt-Br -> pt_BR)', () => {
      store.setCurrentLocale('Pt-Br');
      expect(store.currentLocale).toBe('pt_BR');
    });

    it('falls back to primary code match for unsupported variant (de-CH -> de)', () => {
      store.setCurrentLocale('de-CH');
      expect(store.currentLocale).toBe('de');
    });

    it('falls back to first regional match for unsupported primary-only (it -> it_IT)', () => {
      store.setCurrentLocale('it');
      expect(store.currentLocale).toBe('it_IT');
    });
  });

  describe('unsupported and edge case locales', () => {
    it('falls back to DEFAULT_LOCALE for completely unsupported locale', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'xx' });
      expect(store.currentLocale).toBe(DEFAULT_LOCALE);
    });

    it('handles deviceLocale with unsupported regional variant gracefully', () => {
      const store = useLanguageStore();
      store.init({ deviceLocale: 'fi-FI' });
      expect(store.currentLocale).toBe(DEFAULT_LOCALE);
    });
  });
});
