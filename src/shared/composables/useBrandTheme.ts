// src/shared/composables/useBrandTheme.ts
//
// Bridges the identity store's brand settings to the DOM.
// - Injects palette CSS variables so `bg-brand-*` / `text-brand-*`
//   Tailwind classes reflect the custom domain's brand color.
// - Replaces `<link rel="icon">` href when a custom favicon_url
//   is provided via domain branding.

import { generateBrandPalette } from '@/utils/brand-palette';
import { NEUTRAL_BRAND_DEFAULTS } from '@/shared/constants/brand';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { useAsyncHandler, type AsyncHandlerOptions } from './useAsyncHandler';
import { watch, onScopeDispose } from 'vue';
import { storeToRefs } from 'pinia';

/** Neutral seed used to enumerate the full set of CSS variable keys. */
const SEED_HEX = NEUTRAL_BRAND_DEFAULTS.primary_color;

/** All 44 CSS variable keys produced by generateBrandPalette */
const ALL_KEYS = Object.keys(generateBrandPalette(SEED_HEX));

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

/** Remove all 44 brand CSS overrides so @theme compiled defaults apply */
function clearOverrides(): void {
  const el = document.documentElement;
  for (const key of ALL_KEYS) {
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
  activated = true;

  const identityStore = useProductIdentity();
  const { primaryColor, brand } = storeToRefs(identityStore);

  const asyncHandlerOptions: AsyncHandlerOptions = {
    notify: false,
    onError: () => clearOverrides(),
  };

  const { wrap } = useAsyncHandler(asyncHandlerOptions);

  function applyPalette(color: string | null | undefined): void {
    if (isNeutralColor(color)) {
      clearOverrides();
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

  // Favicon override: when brand settings include a custom favicon_url,
  // update all <link rel="icon"> elements in the document head.
  watch(
    () => brand.value?.favicon_url,
    (faviconUrl) => {
      if (faviconUrl) {
        applyFavicon(faviconUrl);
      } else {
        restoreFavicons();
      }
    },
    { immediate: true }
  );

  onScopeDispose(() => {
    clearOverrides();
    restoreFavicons();
    activated = false;
  });
}
