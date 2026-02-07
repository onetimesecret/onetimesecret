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
import { watch, onScopeDispose } from 'vue';
import { storeToRefs } from 'pinia';

/** All 44 CSS variable keys produced by generateBrandPalette */
const ALL_KEYS = Object.keys(generateBrandPalette(DEFAULT_BRAND_HEX));

function isDefaultColor(hex: string | null | undefined): boolean {
  if (!hex) return true;
  return hex.toLowerCase().replace('#', '')
    === DEFAULT_BRAND_HEX.toLowerCase().replace('#', '');
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

  function applyPalette(color: string | null | undefined): void {
    const el = document.documentElement;

    if (isDefaultColor(color)) {
      // Remove overrides — let @theme compiled defaults apply
      for (const key of ALL_KEYS) {
        el.style.removeProperty(key);
      }
      return;
    }

    const palette = generateBrandPalette(color as string);
    for (const [key, value] of Object.entries(palette)) {
      el.style.setProperty(key, value);
    }
  }

  watch(primaryColor, (newColor) => {
    applyPalette(newColor);
  }, { immediate: true });

  onScopeDispose(() => {
    // Clean up all 44 CSS variables on scope disposal
    const el = document.documentElement;
    for (const key of ALL_KEYS) {
      el.style.removeProperty(key);
    }
  });
}
