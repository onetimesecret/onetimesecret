// src/i18n.ts

import type { BootstrapPayload } from '@/schemas/contracts/bootstrap';
import { type Locale } from '@/schemas/i18n/locale';
import { getBootstrapValue } from '@/services/bootstrap.service';
import {
  createI18n,
  type Composer,
  type DefineLocaleMessage,
  type LocaleMessageValue,
} from 'vue-i18n';

/**
 * Internationalization configuration and utilities.
 * Sets up Vue i18n instances, loads locale messages on demand, and activates
 * a locale only once its messages are registered.
 *
 * Locale files are pre-merged by the Python sync script into single files
 * at generated/locales/{locale}.json, so each locale is one module and no
 * runtime merging is needed.
 */

/** Messages for one locale: the parsed contents of generated/locales/{locale}.json. */
export type LocaleMessages = Record<string, LocaleMessageValue>;

interface LocaleModule {
  default?: LocaleMessages;
}

/**
 * English is bundled with the entry. It is the `default` fallback for every
 * locale (etc/defaults/config.defaults.yaml, internationalization.fallback_locale),
 * so every visitor needs it, and every instance starts on it.
 */
const EAGER_LOCALE = 'en';

/**
 * Import pre-merged locale files from the generated directory. The sync
 * script (locales/scripts/i18n content compile --merged) produces these files
 * during development and build.
 *
 * Note: The patterns are relative to this file, not to the project root. A leading /
 * resolves against the root, which is ./src under vite.config.ts but the repo root
 * under vitest.config.ts, so a root-anchored pattern matched nothing in tests.
 *
 * en is typed as DefineLocaleMessage: generated/types/i18n-keys.d.ts derives
 * that schema from en.json itself.
 */
const eagerModules = import.meta.glob<DefineLocaleMessage>('../generated/locales/en.json', {
  eager: true,
  import: 'default',
});

/**
 * Every other locale is its own lazy chunk. en is excluded so it is not also
 * emitted as a chunk. The module may resolve to undefined: see loadLocaleMessages.
 */
const lazyModules = import.meta.glob<LocaleModule | undefined>([
  '../generated/locales/*.json',
  '!../generated/locales/en.json',
]);

/** Extract the locale code from a glob key: ../generated/locales/bg.json -> bg */
const localeFromPath = (path: string): string | undefined =>
  path.match(/\/locales\/([^/]+)\.json$/)?.[1];

// Maps, not plain objects, so a locale string from a URL or a stored
// preference can never resolve to an Object.prototype member.
const lazyLoaders = new Map<string, () => Promise<LocaleModule | undefined>>();
for (const [path, loader] of Object.entries(lazyModules)) {
  const locale = localeFromPath(path);
  if (locale) lazyLoaders.set(locale, loader);
}

const eagerMessages: DefineLocaleMessage | undefined = Object.entries(eagerModules).find(
  ([path]) => localeFromPath(path) === EAGER_LOCALE
)?.[1];

/** In-flight and settled loads, shared by every instance. */
const messageLoads = new Map<string, Promise<LocaleMessages>>();
if (eagerMessages) messageLoads.set(EAGER_LOCALE, Promise.resolve(eagerMessages));

const hasLocaleMessages = (locale: string): boolean =>
  messageLoads.has(locale) || lazyLoaders.has(locale);

/**
 * Loads the messages for one locale. The cache is shared by every instance:
 * concurrent calls for a locale share one import, and later calls get the
 * settled result. A rejected load is evicted so that a later call retries.
 * 'en' resolves from the bundled import with no request.
 *
 * Rejects for a locale with no generated file and for a chunk that fails to
 * load. A failed chunk import dispatches `vite:preloadError`; the entry points
 * call preventDefault() on it (to reload), and Vite's preload helper then
 * resolves the import with undefined instead of rejecting. That case rejects
 * here too, so undefined is never registered as a locale's messages.
 *
 * Loading does not register or activate anything: each instance registers
 * messages in its own composer (see createI18nInstance).
 */
export function loadLocaleMessages(locale: string): Promise<LocaleMessages> {
  const cached = messageLoads.get(locale);
  if (cached) return cached;

  const loader = lazyLoaders.get(locale);
  if (!loader) {
    return Promise.reject(new Error(`[i18n] No messages exist for locale "${locale}"`));
  }

  const load = loader().then((module) => {
    if (!module?.default) {
      throw new Error(`[i18n] Messages for locale "${locale}" did not load`);
    }
    return module.default;
  });
  messageLoads.set(locale, load);
  load.catch(() => {
    if (messageLoads.get(locale) === load) messageLoads.delete(locale);
  });
  return load;
}

const isFallbackMap = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/**
 * The locales vue-i18n consults for `start`, in order, under `fallback`.
 *
 * This is the walk vue-i18n's default locale fallbacker performs
 * (fallbackWithLocaleChain in @intlify/core-base), repeated here because
 * vue-i18n does not export it. Matching vue-i18n exactly is the point:
 * loading more would not change what it renders. The walk splits tags on
 * hyphens only and looks map keys up by the code itself, so it relies on the
 * map's keys being underscored codes (see normalizeFallbackKeys). With the
 * default config, de_AT resolves to [de_AT, de, en].
 */
function fallbackChain(start: string, fallback: unknown): string[] {
  const chain: string[] = [];

  // Each step returns true to keep walking, false to stop, or a further
  // block of locales to walk (a fallback map entry).
  const appendItem = (target: string, blocks: unknown): unknown => {
    if (chain.includes(target)) return false;
    if (!target) return true;
    let follow: unknown = !target.endsWith('!');
    const locale = target.replace(/!/g, '');
    chain.push(locale);
    if (isFallbackMap(blocks) && Object.hasOwn(blocks, locale) && blocks[locale]) {
      follow = blocks[locale];
    }
    return follow;
  };

  const appendLocale = (locale: string, blocks: unknown): unknown => {
    const tokens = locale.split('-');
    let follow: unknown;
    do {
      follow = appendItem(tokens.join('-'), blocks);
      tokens.pop();
    } while (tokens.length && follow === true);
    return follow;
  };

  const appendBlock = (block: unknown[], blocks: unknown): unknown => {
    let follow: unknown = true;
    for (let i = 0; i < block.length && typeof follow === 'boolean'; i++) {
      const locale = block[i];
      if (typeof locale === 'string') follow = appendLocale(locale, blocks);
    }
    return follow;
  };

  let block: unknown = [start];
  while (Array.isArray(block)) block = appendBlock(block, fallback);

  const defaults = isFallbackMap(fallback) ? (fallback.default ?? null) : fallback;
  block = typeof defaults === 'string' ? [defaults] : defaults;
  if (Array.isArray(block)) appendBlock(block, false);

  return chain;
}

type GlobalComposer = Composer<{}, {}, {}, Locale>;

type FallbackConfig = BootstrapPayload['fallback_locale'];

/**
 * A copy of the fallback map with each key's hyphens turned into underscores
 * (de-AT -> de_AT), the form of our locale codes. The config writes BCP 47
 * keys, and vue-i18n's walk never matches one against an underscored code:
 * unnormalized, de_AT falls straight back to en. The server normalizes the same
 * way for its own reader (normalize_fallback_keys in
 * lib/onetime/application/middleware_stack.rb). Values are already
 * underscored and stay as they are; a string or array config is returned
 * unchanged.
 */
function normalizeFallbackKeys(fallback: FallbackConfig): FallbackConfig {
  if (!isFallbackMap(fallback)) return fallback;
  return Object.fromEntries(
    Object.entries(fallback).map(([key, chain]) => [key.replaceAll('-', '_'), chain])
  );
}

/**
 * The fallback chains come directly from etc/config.yaml
 * (internationalization.fallback_locale), with normalized keys.
 */
const fallbackLocale = normalizeFallbackKeys(getBootstrapValue('fallback_locale') || {});

/**
 * The BCP 47 language tag for one of our locale codes: pt_BR -> pt-BR,
 * de_AT -> de-AT, bg -> bg. Locale files and supported_locales use
 * underscores; `lang` attributes take hyphens.
 */
export function toLanguageTag(locale: string): string {
  return locale.replaceAll('_', '-');
}

/**
 * Builds an i18n instance; see createI18nInstance. `onActivate` runs in the
 * same synchronous step that changes composer.locale, and only for a call
 * that activates its locale. Only the global instance passes one.
 */
function buildI18nInstance(onActivate?: (locale: string) => void) {
  // A new object on every call. vue-i18n keeps the `messages` object as the
  // instance's message store without copying it, and setLocaleMessage writes
  // into it, so one object passed to several instances would share every
  // locale registered later.
  const messages: Record<string, DefineLocaleMessage> = {};
  if (eagerMessages) messages[EAGER_LOCALE] = eagerMessages;

  const instance = createI18n<false>({
    legacy: false, // Enable composition API.
    locale: EAGER_LOCALE,
    fallbackLocale: fallbackLocale,
    globalInjection: true, // allows $t to be used globally.
    missingWarn: true, // these enable browser console logging
    fallbackWarn: true, // and are removed from prod builds.
    messages, // en only; setLocale registers the others on demand.
  });

  /**
   * Access the root Composer for this i18n instance.
   *
   * Vue I18n has a hierarchical structure:
   * - instance.global: The root Composer handling translations at instance level
   * - useI18n(): Component-level Composer that inherits from instance.global
   * - useI18n({ useScope: 'local' }): Isolated component-level Composer
   *
   * Even for non-global instances (like preview instances), we still access
   * the root Composer via .global since it represents the root scope of that
   * specific instance.
   *
   * @see https://vue-i18n.intlify.dev/guide/advanced/scope.html
   */
  const composer = instance.global as GlobalComposer;

  // Locales whose messages this composer holds, tracked here rather than
  // inferred from composer.availableLocales (the keys of its message store).
  const registered = new Set<string>(Object.keys(messages));

  // Incremented by every setLocale call; only the latest call may activate.
  let latestRequest = 0;

  /**
   * Loads `locale` and its fallback chain into this composer, then activates it.
   *
   * Resolves true when this call activated the locale. Resolves false when a
   * newer setLocale call on this instance started before this one settled
   * (whether this one's load succeeded or failed); the locale is left to the
   * newer call. Rejects when a load fails, with the previous locale still
   * active and nothing registered by this call.
   *
   * Messages are registered with setLocaleMessage before composer.locale
   * changes, so the first render in the new locale already has them.
   *
   * @param locale - Target locale code, as named in generated/locales (e.g. bg, de_AT)
   */
  const setLocale = async (locale: string): Promise<boolean> => {
    const request = ++latestRequest;
    const missing = fallbackChain(locale, composer.fallbackLocale.value).filter(
      (code) => !registered.has(code) && (code === locale || hasLocaleMessages(code))
    );

    let loaded: Array<[string, LocaleMessages]>;
    try {
      loaded = await Promise.all(
        missing.map(
          async (code): Promise<[string, LocaleMessages]> => [code, await loadLocaleMessages(code)]
        )
      );
    } catch (error) {
      if (request !== latestRequest) return false;
      throw error;
    }
    if (request !== latestRequest) return false;

    for (const [code, localeMessages] of loaded) {
      composer.setLocaleMessage<LocaleMessages>(code, localeMessages);
      registered.add(code);
    }
    composer.locale.value = locale;
    onActivate?.(locale);
    return true;
  };

  return {
    instance,
    composer,
    setLocale,
  };
}

/**
 * Creates a completely independent i18n instance with its own locale state and message
 * store. The global i18n instance below is built by the same code.
 *
 * This differs from useI18n({ useScope: 'local' }) which only provides component-level
 * message isolation within the global instance. Local scope - still uses global
 * instance but with component-isolated messages. When the global locale changes, the
 * local scope will update accordingly.
 *
 * Use createI18nInstance when you need:
 *
 * - A fully isolated instance that won't affect or be affected by the global app locale
 * - Independent message loading and locale switching
 * - Preview/sandbox functionality that should remain separate from the main app
 * - Testing scenarios where global state isolation is required
 *
 * Every instance starts on 'en', the one locale whose messages are registered
 * at creation, so its composer never reports a locale it cannot render.
 * Activate another locale with `await setLocale(locale)`. Messages are
 * registered per instance: the global instance having Bulgarian does not
 * give a preview instance Bulgarian until the preview calls setLocale('bg').
 *
 * @returns Object containing:
 *   - instance (I18n): The raw i18n instance.
 *   - composer (Composer): The composer for accessing translations.
 *   - setLocale: Loads and activates a locale for this instance only.
 */
export function createI18nInstance() {
  return buildI18nInstance();
}

/**
 * Keeps <html lang> on the global instance's active locale, so content
 * outside the layout root (modals and toasts teleported to <body>) carries
 * the right language too. Preview instances never touch the document.
 */
const setDocumentLanguage = (locale: string) => {
  if (typeof document !== 'undefined') document.documentElement.lang = toLanguageTag(locale);
};

/** Create and export the global instance */
const {
  instance: i18n,
  composer: globalComposer,
  setLocale: setGlobalLocale,
} = buildI18nInstance(setDocumentLanguage);
export default i18n;
export { globalComposer, setGlobalLocale };
