// src/shared/composables/useBrandTheme.ts

import {
  generateBrandPalette,
  DEFAULT_BRAND_HEX,
  BRAND_CSS_VARIABLES,
  _internals,
} from '@/utils/brand-palette';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { storeToRefs } from 'pinia';
import { watch, onScopeDispose } from 'vue';

/**
 * Injects runtime CSS variables on document.documentElement to override the
 * static @theme block from style.css. This bridges the gap between the
 * identityStore's primaryColor and the 290 Tailwind `bg-brand-*` class usages.
 *
 * When primaryColor equals the default (#dc4a22), removes overrides so the
 * compiled @theme defaults take effect (no unnecessary specificity layer).
 *
 * Call once in App.vue after Pinia hydration.
 */
export function useBrandTheme() {
  const identityStore = useProductIdentity();
  const { primaryColor } = storeToRefs(identityStore);

  function applyPalette(color: string | undefined) {
    const root = typeof document !== 'undefined' ? document.documentElement : null;
    if (!root) return;

    const normalized = _internals.normalizeHex(color ?? '');
    const effectiveColor = normalized ?? DEFAULT_BRAND_HEX;

    if (effectiveColor.toLowerCase() === DEFAULT_BRAND_HEX.toLowerCase()) {
      // Default color — remove overrides, let @theme compiled values take effect
      removePalette(root);
      return;
    }

    const palette = generateBrandPalette(effectiveColor);
    for (const [varName, hex] of Object.entries(palette)) {
      root.style.setProperty(varName, hex);
    }
  }

  function removePalette(root: HTMLElement) {
    for (const varName of BRAND_CSS_VARIABLES) {
      root.style.removeProperty(varName);
    }
  }

  // Watch with immediate: true to set vars before first child render
  const stopWatch = watch(primaryColor, (newColor) => {
    applyPalette(newColor);
  }, { immediate: true });

  // Cleanup on scope disposal
  onScopeDispose(() => {
    stopWatch();
    const root = typeof document !== 'undefined' ? document.documentElement : null;
    if (root) {
      removePalette(root);
    }
  });

  return {
    applyPalette,
  };
}
