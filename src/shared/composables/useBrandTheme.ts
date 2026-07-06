// src/shared/composables/useBrandTheme.ts
//
// Bridges the identity store's brand settings to the DOM.
// - Injects palette CSS variables so `bg-brand-*` / `text-brand-*`
//   Tailwind classes reflect the custom domain's brand color.
// - Replaces `<link rel="icon">` href when a custom favicon_url
//   is provided via domain branding.

import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { borderRadiusToCss } from '@/shared/utils/brand-helpers';
import { generateBrandPalette, generateNamedScale } from '@/utils/brand-palette';
import { storeToRefs } from 'pinia';
import { computed, watch, onScopeDispose } from 'vue';

import { useAsyncHandler, type AsyncHandlerOptions } from './useAsyncHandler';

/** Neutral seed used to enumerate the full set of CSS variable keys. */
const SEED_HEX = NEUTRAL_BRAND_DEFAULTS.primary_color;

/** All 44 CSS variable keys produced by generateBrandPalette */
const ALL_KEYS = Object.keys(generateBrandPalette(SEED_HEX));

/** CSS variable group for the secondary color scale (#3646). */
const SECONDARY_PREFIX = 'brand2';

/** The 11 `--color-brand2-*` keys produced for the secondary scale. */
const SECONDARY_KEYS = Object.keys(generateNamedScale(SEED_HEX, SECONDARY_PREFIX));

/**
 * Single-value tokens injected from the expanded vocabulary. Each has a
 * compiled `@theme static` default in style.css, so removing the override here
 * cleanly falls back rather than resolving to nothing.
 */
const BG_KEY = '--color-brandbg';
const TEXT_KEY = '--color-brandtext';
const RADIUS_KEY = '--radius-brand';

/** Every extended-token key we may set, for wholesale clearing. */
const EXTENDED_KEYS = [...SECONDARY_KEYS, BG_KEY, TEXT_KEY, RADIUS_KEY];

/** Single-entry memoization cache for palette generation */
let cachedHex: string | null = null;
let cachedPalette: Record<string, string> | null = null;

function memoizedGeneratePalette(hex: string): Record<string, string> {
  if (hex === cachedHex && cachedPalette) return cachedPalette;
  cachedPalette = generateBrandPalette(hex);
  cachedHex = hex;
  return cachedPalette;
}

/** Single-entry guard ensuring the composable activates only once per page. */
let activated = false;

function normalize(hex: string | null | undefined): string | null {
  if (!hex) return null;
  return hex.toLowerCase().replace('#', '');
}

function isNeutralColor(hex: string | null | undefined): boolean {
  const normalized = normalize(hex);
  if (!normalized) return true;
  return normalized === normalize(NEUTRAL_BRAND_DEFAULTS.primary_color);
}

/** Remove the 44 primary-palette overrides so @theme defaults apply. Leaves
 * the independent extended tokens (secondary/bg/text/radius) untouched — a
 * neutral primary can still coexist with a custom secondary color. */
function clearPrimaryOverrides(): void {
  const el = document.documentElement;
  for (const key of ALL_KEYS) {
    el.style.removeProperty(key);
  }
}

/** Remove ALL brand CSS overrides (primary palette + extended tokens) so
 * @theme compiled defaults apply. Used on dispose and error. */
function clearOverrides(): void {
  const el = document.documentElement;
  for (const key of [...ALL_KEYS, ...EXTENDED_KEYS]) {
    el.style.removeProperty(key);
  }
}

/**
 * Injects (or clears) the expanded brand tokens from #3646:
 *   - secondary_color  → `--color-brand2-*` 11-shade scale
 *   - background_color → `--color-brandbg`
 *   - text_color       → `--color-brandtext`
 *   - border_radius    → `--radius-brand`
 *
 * Each token is independent: an unset field removes its override so the
 * compiled `@theme static` default applies. Fonts are handled via utility
 * classes (fontFamilyClasses), not here.
 */
function applyExtendedTokens(brand: {
  secondary_color?: string | null;
  background_color?: string | null;
  text_color?: string | null;
  border_radius?: string | number | null;
} | null | undefined): void {
  const el = document.documentElement;

  // Secondary color scale.
  const secondary = brand?.secondary_color;
  if (secondary && !isNeutralColor(secondary)) {
    const scale = generateNamedScale(secondary, SECONDARY_PREFIX);
    for (const [key, value] of Object.entries(scale)) {
      el.style.setProperty(key, value);
    }
  } else {
    for (const key of SECONDARY_KEYS) el.style.removeProperty(key);
  }

  // Single-value surface/ink tokens.
  setOrClear(el, BG_KEY, brand?.background_color ?? null);
  setOrClear(el, TEXT_KEY, brand?.text_color ?? null);

  // Border radius: resolve preset/px to a CSS length.
  setOrClear(el, RADIUS_KEY, borderRadiusToCss(brand?.border_radius ?? null));
}

/** Sets a CSS custom property when `value` is truthy, otherwise removes it. */
function setOrClear(el: HTMLElement, key: string, value: string | null): void {
  if (value) {
    el.style.setProperty(key, value);
  } else {
    el.style.removeProperty(key);
  }
}

/** Snapshot of original favicon hrefs so we can restore on dispose */
let originalFaviconHrefs: Map<Element, string> | null = null;

/**
 * Updates all `<link rel="icon">` and `<link rel="shortcut icon">` elements
 * to point at the given URL. Saves originals for later restoration.
 */
function applyFavicon(url: string): void {
  const links = document.querySelectorAll<HTMLLinkElement>(
    'link[rel="icon"], link[rel="shortcut icon"]'
  );
  if (!links.length) return;

  if (!originalFaviconHrefs) {
    originalFaviconHrefs = new Map();
    links.forEach((link) => originalFaviconHrefs!.set(link, link.href));
  }

  links.forEach((link) => {
    link.href = url;
  });
}

/** Restores original favicon hrefs captured before the first override */
function restoreFavicons(): void {
  if (!originalFaviconHrefs) return;
  originalFaviconHrefs.forEach((href, link) => {
    if (link instanceof HTMLLinkElement) {
      link.href = href;
    }
  });
  originalFaviconHrefs = null;
}

/**
 * Injects brand palette CSS variables onto the document root
 * element, reactively tracking the identity store's primaryColor.
 *
 * Call once in App.vue to activate the bridge. Subsequent calls
 * within the same page lifecycle are no-ops (single-entry guard).
 */
export function useBrandTheme(): void {
  if (activated) return;
  // SSR/prerender guard: this bridge manipulates the DOM (palette CSS vars on
  // <html> and <link rel="icon"> hrefs). No-op without a DOM, matching the
  // window guards used elsewhere (e.g. useTheme.ts).
  if (typeof window === 'undefined') return;
  activated = true;

  const identityStore = useProductIdentity();
  const { primaryColor, brand } = storeToRefs(identityStore);
  const bootstrapStore = useBootstrapStore();

  const asyncHandlerOptions: AsyncHandlerOptions = {
    notify: false,
    onError: () => clearOverrides(),
  };

  const { wrap } = useAsyncHandler(asyncHandlerOptions);

  function applyPalette(color: string | null | undefined): void {
    if (isNeutralColor(color)) {
      clearPrimaryOverrides();
      return;
    }

    wrap(async () => {
      const palette = memoizedGeneratePalette(color as string);
      const el = document.documentElement;
      for (const [key, value] of Object.entries(palette)) {
        el.style.setProperty(key, value);
      }
    });
  }

  watch(primaryColor, (newColor) => {
    applyPalette(newColor);
  }, { immediate: true });

  // Expanded vocabulary (#3646): secondary color scale + surface/ink/radius
  // tokens. Watches the whole brand object so any of these fields re-injects.
  watch(brand, (newBrand) => {
    wrap(async () => applyExtendedTokens(newBrand));
  }, { immediate: true, deep: true });

  // Favicon override: per-domain favicon_url takes priority, then
  // installation-level brand_favicon_url from bootstrap config.
  const effectiveFaviconUrl = computed(() =>
    brand.value?.favicon_url || bootstrapStore.brand_favicon_url
  );

  watch(effectiveFaviconUrl, (faviconUrl) => {
    if (faviconUrl) {
      applyFavicon(faviconUrl);
    } else {
      restoreFavicons();
    }
  }, { immediate: true });

  onScopeDispose(() => {
    clearOverrides();
    restoreFavicons();
    activated = false;
  });
}
