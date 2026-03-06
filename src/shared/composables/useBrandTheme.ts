// src/shared/composables/useBrandTheme.ts
//
// Bridges the identity store's brand settings to the DOM.
// - Injects palette CSS variables so `bg-brand-*` / `text-brand-*`
//   Tailwind classes reflect the custom domain's brand color.
// - Replaces `<link rel="icon">` href when a custom favicon_url
//   is provided via domain branding.

import {
  generateBrandPalette,
  DEFAULT_BRAND_HEX,
} from '@/utils/brand-palette';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { useAsyncHandler, type AsyncHandlerOptions } from './useAsyncHandler';
import { watch, onScopeDispose } from 'vue';
import { storeToRefs } from 'pinia';

/** All 44 CSS variable keys produced by generateBrandPalette */
const ALL_KEYS = Object.keys(generateBrandPalette(DEFAULT_BRAND_HEX));

/** Single-entry memoization cache for palette generation */
let cachedHex: string | null = null;
let cachedPalette: Record<string, string> | null = null;

function memoizedGeneratePalette(hex: string): Record<string, string> {
  if (hex === cachedHex && cachedPalette) return cachedPalette;
  cachedPalette = generateBrandPalette(hex);
  cachedHex = hex;
  return cachedPalette;
}

function isDefaultColor(hex: string | null | undefined): boolean {
  if (!hex) return true;
  return hex.toLowerCase().replace('#', '')
    === DEFAULT_BRAND_HEX.toLowerCase().replace('#', '');
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
 * Call once in App.vue to activate the bridge.
 */
export function useBrandTheme(): void {
  const identityStore = useProductIdentity();
  const { primaryColor, brand } = storeToRefs(identityStore);

  const asyncHandlerOptions: AsyncHandlerOptions = {
    notify: false,
    onError: () => clearOverrides(),
  };

  const { wrap } = useAsyncHandler(asyncHandlerOptions);

  function applyPalette(color: string | null | undefined): void {
    if (isDefaultColor(color)) {
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
  });
}
