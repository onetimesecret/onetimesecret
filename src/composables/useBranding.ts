// src/composables/useBranding.ts
import { ImageProps, type BrandSettings } from '@/schemas/models/domain';
import { useNotificationsStore } from '@/stores';
import { useDomainsStore } from '@/stores/domainsStore';
import { detectPlatform, shouldUseLightText } from '@/utils';
import { computed, onMounted, ref, watch } from 'vue';
import { createError, useAsyncHandler } from './useAsyncHandler';

/**
 * Composable for displaying domain-specific branding settings
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
/* eslint max-lines-per-function: off */
export function useBranding(domainId?: string) {
  // Add default brand settings
  const defaultBranding: BrandSettings = {
    primary_color: '#000000',
    font_family: 'sans',
    corner_style: 'rounded',
    button_text_light: true,
    instructions_pre_reveal: '',
    instructions_post_reveal: '',
    instructions_reveal: '',
    allow_public_api: false,
    allow_public_homepage: false,
  };

  const store = useDomainsStore();
  const notifications = useNotificationsStore();

  // State
  const isLoading = ref(false);
  const error = ref<string | null>(null);

  const { wrap } = useAsyncHandler({
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isLoading.value = loading),
    // onError: (err) => (error.value = err),
  });

  const initialize = () =>
    wrap(async () => {
      if (!domainId) return;
      const [settings, logo] = await Promise.all([
        store.getBrandSettings(domainId),
        store.fetchLogo(domainId).catch(() => null),
      ]);

      // Important: Set both refs with the fetched settings
      brand.value = { ...settings };
      brandSettings.value = { ...settings };
      originalSettings.value = { ...settings };
      logoImage.value = logo;
    });

  onMounted(initialize);

  const logoImage = ref<ImageProps | null>(null);
  const brand = ref<BrandSettings>(defaultBranding);
  const brandSettings = ref<BrandSettings>({ ...defaultBranding });

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
    (newValue) => {
      if (newValue) {
        brandSettings.value = { ...newValue };
      }
    }
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

    // Compare only serializable properties
    const compare = (a: BrandSettings, b: BrandSettings) => {
      const keys: (keyof BrandSettings)[] = [
        'primary_color',
        'font_family',
        'corner_style',
        'button_text_light',
        'instructions_pre_reveal',
        'instructions_post_reveal',
      ];

      return keys.some((key) => a[key] !== b[key]);
    };

    return compare(brandSettings.value, originalSettings.value);
  });

  // Methods
  const fetchBranding = () =>
    wrap(async () => {
      if (!domainId) throw createError('No domain ID provided', 'human');
      const result = await store.getBrandSettings(domainId);
      brand.value = { ...result };
      originalSettings.value = { ...result };
    });

  const saveBranding = (updates: Partial<BrandSettings>) =>
    wrap(async () => {
      if (!domainId) return;
      await store.updateBrandSettings(domainId, updates);
      originalSettings.value = { ...brandSettings.value, ...updates };
      notifications.show('Brand settings saved successfully', 'success');
    });

  const handleLogoUpload = (file: File) =>
    wrap(async () => {
      if (!domainId) return;

      const uploadedLogo = await store.uploadLogo(domainId, file);
      logoImage.value = uploadedLogo;
      notifications.show('Logo uploaded successfully', 'success');
    });

  const removeLogo = () =>
    wrap(async () => {
      if (!domainId) return;
      await store.removeLogo(domainId);
      logoImage.value = null;
      notifications.show('Logo removed successfully', 'success');
    });

  const submitBrandSettings = (settings?: BrandSettings) =>
    wrap(async () => {
      if (!domainId) return;

      // Use either passed settings or current brandSettings
      const brandData = settings || brandSettings.value;
      if (!brandData) throw createError('No brand settings to save', 'human');

      const payload = {
        brand: {
          primary_color: brandData.primary_color,
          font_family: brandData.font_family,
          corner_style: brandData.corner_style,
          button_text_light: brandData.button_text_light,
          instructions_pre_reveal: brandData.instructions_pre_reveal,
          instructions_post_reveal: brandData.instructions_post_reveal,
          instructions_reveal: brandData.instructions_reveal,
        },
      };

      await store.updateDomainBrand(domainId, payload);
      originalSettings.value = { ...brandData };
      notifications.show('Brand settings saved successfully', 'success');
    });

  return {
    initialize,

    // State
    isLoading,
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

    color: computed(() => primaryColor.value),

    // Methods
    fetchBranding,
    detectPlatform,
    saveBranding,
    submitBrandSettings,
    handleLogoUpload,
    removeLogo,
  };
}
