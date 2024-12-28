// src/composables/useDomainBranding.ts
import { type BrandSettings } from '@/schemas/models/domain';
import { useDomainsStore } from '@/stores/domainsStore';
import { computed, type ComputedRef } from 'vue';

// Use this improved composable/and/store approach for window props
// Use only validated window props, inside window.onetime object
// Add API endpoint for fetching the exact window props that are included in the onetime object
// Get generating tests goddammit.
//
/**
 * Composable for domain-specific branding settings and related UI helpers
 *
 * Separate from useDomainsManager which handles full domain CRUD. This one
 * focuses on the expression of brand settings and UI styling based on domain.
 *
 * Features:
 * - Computed access to brand settings with fallback to defaults
 * - Type-safe brand property getters
 * - UI helper methods for brand-specific styling
 *
 * @param domainId Optional domain ID to fetch specific branding
 * @returns Brand settings and computed helpers
 *
 */
export function useDomainBranding(domainId?: string) {
  const store = useDomainsStore();

  const brandSettings: ComputedRef<BrandSettings> = computed(() => {
    if (!domainId) return store.defaultBranding;

    const domain = store.getDomainById(domainId);
    return domain?.brand || store.defaultBranding;
  });

  const primaryColor = computed(() => brandSettings.value.primary_color);
  const fontFamily = computed(() => brandSettings.value.font_family);
  const cornerStyle = computed(() => brandSettings.value.corner_style);

  const hasCustomBranding = computed(() => brandSettings.value !== store.defaultBranding);

  const getButtonClass = computed(() => ({
    'text-light': brandSettings.value.button_text_light,
    [`corner-${brandSettings.value.corner_style}`]: true,
  }));

  return {
    brandSettings,
    primaryColor,
    fontFamily,
    cornerStyle,
    hasCustomBranding,
    getButtonClass,
  };
}
