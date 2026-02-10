// src/shared/composables/useBrandTheme.ts
//
// Bridges the identity store's primaryColor to Tailwind CSS
// variables on document.documentElement. When a custom domain
// supplies a brand color, every `bg-brand-*` / `text-brand-*`
// Tailwind class automatically reflects that color.

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

/**
 * Injects brand palette CSS variables onto the document root
 * element, reactively tracking the identity store's primaryColor.
 *
 * Call once in App.vue to activate the bridge.
 */
export function useBrandTheme(): void {
  const identityStore = useProductIdentity();
  const { primaryColor } = storeToRefs(identityStore);

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

  onScopeDispose(() => clearOverrides());
}
