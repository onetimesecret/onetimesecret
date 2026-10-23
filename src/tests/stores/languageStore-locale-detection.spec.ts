// src/tests/stores/languageStore-locale-detection.spec.ts
//
// Browser language detection and the locale preference hierarchy in
// languageStore (issue #2668: regional browser locales such as it-IT must
// resolve to the underscored supported locale it_IT).
//
// init() normalizes the device locale against the supported list and returns
// preferredLocale(): account preference > in-session selection > custom-domain
// brand locale > device locale > the installation's default_locale > 'en'.
// Neither activates anything; the router does that with setCurrentLocale(),
// which is covered at the end of this file.

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { DEFAULT_LOCALE, useLanguageStore } from '@/shared/stores/languageStore';
import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { baseBootstrap, mockCustomer } from '@/tests/fixtures/bootstrap.fixture';
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

  /** A custom domain's brand settings with the given Delivery language. */
  const brandLocale = (locale: string): BootstrapPayload['domain_branding'] => ({
    ...(baseBootstrap.domain_branding as NonNullable<BootstrapPayload['domain_branding']>),
    locale,
  });

  beforeEach(async () => {
    // This spec drives init() itself (own options and timing), so the
    // auto-init plugin is off; see SetupTestPiniaOptions.autoInit.
    const setup = await setupTestPinia({ autoInit: false });
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

  /** The preferred locale init() reports for these options; checks the getters agree. */
  function preferredAfterInit(options?: { deviceLocale?: string }): string {
    const store = useLanguageStore();
    const preferred = store.init(options);
    expect(store.preferredLocale()).toBe(preferred);
    expect(store.getCurrentLocale).toBe(preferred);
    return preferred;
  }

  describe('init() activates nothing', () => {
    it('leaves currentLocale null and reports the preferred locale through getCurrentLocale', () => {
      const store = useLanguageStore();

      expect(store.init({ deviceLocale: 'it-IT' })).toBe('it_IT');

      expect(store.currentLocale).toBeNull();
      expect(store.getCurrentLocale).toBe('it_IT');
    });
  });

  describe('init() with deviceLocale for regional variants', () => {
    it.each([
      ['it-IT', 'it_IT'],
      ['fr-FR', 'fr_FR'],
      ['pt-BR', 'pt_BR'],
      ['de-AT', 'de_AT'],
      ['sv-SE', 'sv_SE'],
      ['el-GR', 'el_GR'],
    ])('resolves deviceLocale "%s" to "%s"', (deviceLocale, expected) => {
      expect(preferredAfterInit({ deviceLocale })).toBe(expected);
    });
  });

  describe('init() with primary-only deviceLocale falling back to regional variant', () => {
    it('resolves deviceLocale "fr" to first matching fr variant', () => {
      // "fr" is not in supported_locales, but fr_CA and fr_FR are.
      expect(['fr_CA', 'fr_FR']).toContain(preferredAfterInit({ deviceLocale: 'fr' }));
    });

    it('resolves deviceLocale "it" to "it_IT" (only it variant)', () => {
      expect(preferredAfterInit({ deviceLocale: 'it' })).toBe('it_IT');
    });

    it('resolves deviceLocale "pt" to first matching pt variant', () => {
      expect(['pt_BR', 'pt_PT']).toContain(preferredAfterInit({ deviceLocale: 'pt' }));
    });

    it('resolves deviceLocale "sv" to "sv_SE"', () => {
      expect(preferredAfterInit({ deviceLocale: 'sv' })).toBe('sv_SE');
    });

    it('resolves deviceLocale "da" to "da_DK"', () => {
      expect(preferredAfterInit({ deviceLocale: 'da' })).toBe('da_DK');
    });
  });

  describe('init() with simple locale codes', () => {
    it.each(['de', 'ja', 'es', 'en'])('resolves deviceLocale "%s" directly', (deviceLocale) => {
      expect(preferredAfterInit({ deviceLocale })).toBe(deviceLocale);
    });
  });

  describe('init() without deviceLocale falls back to DEFAULT_LOCALE', () => {
    it('uses DEFAULT_LOCALE when no deviceLocale provided', () => {
      expect(preferredAfterInit()).toBe(DEFAULT_LOCALE);
    });

    it('uses DEFAULT_LOCALE when deviceLocale is undefined', () => {
      expect(preferredAfterInit({ deviceLocale: undefined })).toBe(DEFAULT_LOCALE);
    });
  });

  describe('locale priority: user preference > session storage > domain locale > deviceLocale', () => {
    it('user preference takes priority over deviceLocale', () => {
      bootstrapStore.update({
        supported_locales: fullSupportedLocales,
        cust: { ...mockCustomer, locale: 'ja' },
      });

      expect(preferredAfterInit({ deviceLocale: 'it-IT' })).toBe('ja');
    });

    it('session storage takes priority over deviceLocale', () => {
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue('es');

      expect(preferredAfterInit({ deviceLocale: 'fr-FR' })).toBe('es');
    });

    it('deviceLocale is used when no user preference and no session storage', () => {
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue(null);

      expect(preferredAfterInit({ deviceLocale: 'it-IT' })).toBe('it_IT');
    });

    it('session storage with unsupported locale falls through to deviceLocale', () => {
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue('xx_YY');

      // When deviceLocale is 'de-AT' and both 'de' and 'de_AT' exist in supported
      // locales, the exact regional match 'de_AT' should be preferred over
      // the primary code 'de'.
      expect(preferredAfterInit({ deviceLocale: 'de-AT' })).toBe('de_AT');
    });

    // A recipient on a custom domain sees the domain's Delivery language,
    // ahead of their browser's.
    it('the custom-domain brand locale wins over deviceLocale', () => {
      bootstrapStore.update({ domain_branding: brandLocale('bg') });

      expect(preferredAfterInit({ deviceLocale: 'it-IT' })).toBe('bg');
    });

    it('session storage wins over the custom-domain brand locale', () => {
      bootstrapStore.update({ domain_branding: brandLocale('bg') });
      vi.spyOn(sessionStorage, 'getItem').mockReturnValue('es');

      expect(preferredAfterInit({ deviceLocale: 'it-IT' })).toBe('es');
    });

    it('user preference wins over the custom-domain brand locale', () => {
      bootstrapStore.update({
        cust: { ...mockCustomer, locale: 'ja' },
        domain_branding: brandLocale('bg'),
      });

      expect(preferredAfterInit({ deviceLocale: 'it-IT' })).toBe('ja');
    });

    it('an unsupported brand locale falls through to deviceLocale', () => {
      bootstrapStore.update({ domain_branding: brandLocale('xx') });

      expect(preferredAfterInit({ deviceLocale: 'it-IT' })).toBe('it_IT');
    });

    // preferredLocale() reads the bootstrap snapshot on every call, so an auth
    // refresh that swaps the customer changes the answer.
    it('follows a customer swapped in after init()', () => {
      const store = useLanguageStore();
      expect(store.init({ deviceLocale: 'it-IT' })).toBe('it_IT');

      bootstrapStore.update({ cust: { ...mockCustomer, locale: 'ja' } });

      expect(store.preferredLocale()).toBe('ja');
      expect(store.getCurrentLocale).toBe('ja');
    });
  });

  describe("the installation's default_locale, then 'en'", () => {
    it('uses a supported default_locale when nothing else matches', () => {
      bootstrapStore.update({ supported_locales: ['de', 'fr_FR'], default_locale: 'de' });

      expect(preferredAfterInit({ deviceLocale: 'ja' })).toBe('de');
    });

    it('passes over an unsupported default_locale', () => {
      bootstrapStore.update({ supported_locales: ['de', 'fr_FR'], default_locale: 'xx' });

      expect(preferredAfterInit({ deviceLocale: 'ja' })).toBe(DEFAULT_LOCALE);
    });

    // F4: an operator's locale list that omits 'en' must not leave the
    // visitor without a locale: 'en' is always accepted and always activates.
    it("ends in 'en' when the supported list omits it, and 'en' activates", async () => {
      bootstrapStore.update({ supported_locales: ['de', 'fr_FR'], default_locale: 'xx' });
      const store = useLanguageStore();

      expect(store.init()).toBe(DEFAULT_LOCALE);
      expect(store.resolveSupportedLocale('en')).toBe('en');
      expect(store.resolveSupportedLocale('EN')).toBe('en');
      expect(store.resolveSupportedLocale('en-US')).toBeNull();
      await expect(store.setCurrentLocale(store.preferredLocale())).resolves.toBe('en');
      expect(store.currentLocale).toBe('en');
    });

    it("ends in 'en' when the supported list is empty", async () => {
      bootstrapStore.update({ supported_locales: [] });
      const store = useLanguageStore();

      expect(store.init({ deviceLocale: 'de' })).toBe(DEFAULT_LOCALE);
      await expect(store.setCurrentLocale(store.preferredLocale())).resolves.toBe('en');
    });
  });

  // ---------------------------------------------------------------
  // validateAndNormalizeLocale when called via setCurrentLocale, where
  // supportedLocales is already populated. Each call loads the locale's
  // messages (and its fallback chain) before it resolves.
  // ---------------------------------------------------------------
  describe('validateAndNormalizeLocale via setCurrentLocale', () => {
    let store: ReturnType<typeof useLanguageStore>;

    beforeEach(() => {
      store = useLanguageStore();
      store.supportedLocales = fullSupportedLocales;
    });

    it.each([
      ['it-IT', 'it_IT', 'converts hyphen to underscore'],
      ['IT-it', 'it_IT', 'handles case insensitivity'],
      ['FR_FR', 'fr_FR', 'handles uppercase with underscore'],
      ['Pt-Br', 'pt_BR', 'handles mixed case with hyphen'],
      ['de-CH', 'de', 'falls back to primary code match for unsupported variant'],
      ['it', 'it_IT', 'falls back to first regional match for unsupported primary-only'],
    ])('%s -> %s (%s)', async (input, expected) => {
      await expect(store.setCurrentLocale(input)).resolves.toBe(expected);
      expect(store.currentLocale).toBe(expected);
    });
  });

  describe('unsupported and edge case locales', () => {
    it('falls back to DEFAULT_LOCALE for completely unsupported locale', () => {
      expect(preferredAfterInit({ deviceLocale: 'xx' })).toBe(DEFAULT_LOCALE);
    });

    it('handles deviceLocale with unsupported regional variant gracefully', () => {
      expect(preferredAfterInit({ deviceLocale: 'fi-FI' })).toBe(DEFAULT_LOCALE);
    });
  });
});
