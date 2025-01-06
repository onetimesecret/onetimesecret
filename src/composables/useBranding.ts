// src/composables/useBranding.ts
import { ImageProps, type BrandSettings } from '@/schemas/models/domain';
import { loggingService } from '@/services/logging';
import { useNotificationsStore } from '@/stores';
import { useDomainsStore } from '@/stores/domainsStore';
import { shouldUseLightText } from '@/utils';
import { computed, onMounted, ref, watch } from 'vue';

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

  const initialize = async () => {
    if (!domainId) return;

    isLoading.value = true;
    try {
      const settings = await store.getBrandSettings(domainId);
      brand.value = settings;
      brandSettings.value = { ...settings };
    } catch (err) {
      error.value = err instanceof Error ? err.message : 'Failed to load settings';
    } finally {
      isLoading.value = false;
    }
  };

  onMounted(initialize);

  const store = useDomainsStore();
  const notifications = useNotificationsStore();

  // State
  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const logoImage = ref<ImageProps | null>(null);

  const brand = ref<BrandSettings>(defaultBranding);

  const brandSettings = ref<BrandSettings>({ ...defaultBranding });

  const primaryColor = computed(() => brandSettings.value.primary_color);
  const fontFamily = computed(() => brandSettings.value.font_family);
  const cornerStyle = computed(() => brandSettings.value.corner_style);
  const hasCustomBranding = computed(() => brandSettings.value !== store.defaultBranding);
  const selectedBrowserType = computed(() => detectPlatform());
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
  const fetchBranding = async () => {
    if (!domainId) {
      error.value = 'No domain ID provided';
      return;
    }

    isLoading.value = true;
    try {
      const result = await store.getBrandSettings(domainId);
      brand.value = result;
      originalSettings.value = { ...result };
    } catch (err) {
      error.value = err instanceof Error ? err.message : 'Failed to fetch brand settings';
      throw err; // Allow parent to handle
    } finally {
      isLoading.value = false;
    }
  };

  const saveBranding = async (updates: Partial<BrandSettings>) => {
    if (!domainId) return;

    isLoading.value = true;
    try {
      await store.updateBrandSettings(domainId, updates);
      originalSettings.value = { ...brandSettings.value, ...updates };
      notifications.show('Brand settings saved successfully', 'success');
    } catch (err) {
      notifications.show('Failed to save brand settings', 'error');
      throw err;
    } finally {
      isLoading.value = false;
    }
  };

  // Logo management
  const handleLogoUpload = async (file: File) => {
    if (!domainId) return;

    isLoading.value = true;
    try {
      await store.uploadLogo(domainId, file);
      logoImage.value = await store.fetchLogo(domainId);
      notifications.show('Logo uploaded successfully', 'success');
    } catch (err) {
      notifications.show('Failed to upload logo', 'error');
      loggingService.info('Failed to upload logo', { error: err });
    } finally {
      isLoading.value = false;
    }
  };

  const removeLogo = async () => {
    try {
      isLoading.value = true;
      await store.removeLogo(domainId);
      logoImage.value = null;
      notifications.show('Logo removed successfully', 'success');
    } catch (err) {
      notifications.show('Failed to remove logo', 'error');
      loggingService.info('Failed to upload logo', { error: err });
    } finally {
      isLoading.value = false;
    }
  };

  const detectPlatform = (): 'safari' | 'edge' => {
    const ua = window.navigator.userAgent.toLowerCase();
    const isMac = /macintosh|mac os x|iphone|ipad|ipod/.test(ua);
    return isMac ? 'safari' : 'edge';
  };

  const submitBrandSettings = async (settings: BrandSettings) => {
    if (!domainId) return;

    isLoading.value = true;
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
      isLoading.value = false;
    }
  };

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

    selectedBrowserType: ref(detectPlatform()),
    color: computed(() => primaryColor.value),
    toggleBrowser: () => {
      selectedBrowserType.value =
        selectedBrowserType.value === 'safari' ? 'edge' : 'safari';
    },

    // Methods
    fetchBranding,
    detectPlatform,
    saveBranding,
    submitBrandSettings,
    handleLogoUpload,
    removeLogo,
  };
}
