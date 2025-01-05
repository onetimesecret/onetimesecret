// src/composables/useDomainBranding.ts
import { ImageProps, type BrandSettings } from '@/schemas/models/domain';
import { useNotificationsStore } from '@/stores';
import { useDomainsStore } from '@/stores/domainsStore';
import { shouldUseLightText } from '@/utils';
import { computed, ref, watch } from 'vue';

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
  const notifications = useNotificationsStore();

  // State
  const loading = ref(false);
  const error = ref<string | null>(null);
  const logoImage = ref<ImageProps | null>(null);

  const brand = ref<BrandSettings | null>(null);

  // Computed properties from existing implementation
  const brandSettings = computed(() => {
    if (!brand.value) return store.defaultBranding;
    return brand.value;
  });

  const primaryColor = computed(() => brandSettings.value.primary_color);
  const fontFamily = computed(() => brandSettings.value.font_family);
  const cornerStyle = computed(() => brandSettings.value.corner_style);
  const hasCustomBranding = computed(() => brandSettings.value !== store.defaultBranding);
  const getButtonClass = computed(() => ({
    'text-light': brandSettings.value.button_text_light,
    [`corner-${brandSettings.value.corner_style}`]: true,
  }));

  // Track changes between current and original settings
  watch(
    () => brand.value,
    () => {
      if (originalSettings.value) {
        hasUnsavedChanges.value =
          JSON.stringify(brandSettings.value) !== JSON.stringify(originalSettings.value);
      }
    },
    { deep: true }
  );

  // Auto-adjust text color based on background
  watch(
    () => primaryColor,
    (newColor) => {
      if (newColor) {
        brandSettings.value.button_text_light = shouldUseLightText(newColor);
      }
    }
  );

  // Track changes
  const originalSettings = ref<BrandSettings | null>(null);
  const hasUnsavedChanges = computed(() => {
    if (!originalSettings.value) return false;
    return JSON.stringify(brandSettings.value) !== JSON.stringify(originalSettings.value);
  });

  // Methods
  const fetchBranding = async () => {
    if (!domainId) return;

    loading.value = true;
    try {
      brand.value = await store.getBrandSettings(domainId);
      originalSettings.value = brand;
    } catch (err) {
      error.value = err instanceof Error ? err.message : 'Failed to fetch brand settings';
    } finally {
      loading.value = false;
    }
  };

  const saveBranding = async (updates: Partial<BrandSettings>) => {
    if (!domainId) return;

    loading.value = true;
    try {
      await store.updateBrandSettings(domainId, updates);
      originalSettings.value = { ...brandSettings.value, ...updates };
      notifications.show('Brand settings saved successfully', 'success');
    } catch (err) {
      notifications.show('Failed to save brand settings', 'error');
      throw err;
    } finally {
      loading.value = false;
    }
  };

  // Logo management
  const handleLogoUpload = async (file: File) => {
    if (!domainId) return;

    loading.value = true;
    try {
      await store.uploadLogo(domainId, file);
      logoImage.value = await store.fetchLogo(domainId);
      notifications.show('Logo uploaded successfully', 'success');
    } catch (err) {
      notifications.show('Failed to upload logo', 'error');
    } finally {
      loading.value = false;
    }
  };

  const removeLogo = async () => {
    try {
      loading.value = true;
      await store.removeLogo(domainId);
      logoImage.value = null;
      notifications.show('Logo removed successfully', 'success');
    } catch (err) {
      notifications.show('Failed to remove logo', 'error');
    } finally {
      loading.value = false;
    }
  };

  const detectPlatform = (): 'safari' | 'edge' => {
    const ua = window.navigator.userAgent.toLowerCase();
    const isMac = /macintosh|mac os x|iphone|ipad|ipod/.test(ua);
    return isMac ? 'safari' : 'edge';
  };

  const submitBrandSettings = async (settings: BrandSettings) => {
    if (!domainId) return;

    loading.value = true;
    try {
      // Create payload with CSRF token
      const payload = {
        brand: {
          primary_color: settings.primary_color,
          font_family: settings.font_family,
          corner_style: settings.corner_style,
          button_text_light: settings.button_text_light,
          instructions_pre_reveal: settings.instructions_pre_reveal,
          instructions_post_reveal: settings.instructions_post_reveal,
          instructions_reveal: settings.instructions_reveal,
        },
      };

      await store.updateDomainBrand(domainId, payload);
      originalSettings.value = { ...settings };
      hasUnsavedChanges.value = false;
      notifications.show('Brand settings saved successfully', 'success');
    } catch (err) {
      notifications.show(
        err instanceof Error ? err.message : 'Failed to save brand settings',
        'error'
      );
    } finally {
      loading.value = false;
    }
  };

  return {
    // State
    loading,
    error,
    logoImage,
    brand,

    // Computed
    brandSettings,
    primaryColor,
    fontFamily,
    cornerStyle,
    hasCustomBranding,
    getButtonClass,
    hasUnsavedChanges,

    // Methods
    fetchBranding,
    detectPlatform,
    saveBranding,
    submitBrandSettings,
    handleLogoUpload,
    removeLogo,
  };
}
