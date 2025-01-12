import { ImageProps, type BrandSettings } from '@/schemas/models';
import { useNotificationsStore } from '@/stores';
import { useBrandStore } from '@/stores/brandStore';
import { shouldUseLightText } from '@/utils';
import { computed, onMounted, ref, watch } from 'vue';
import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';
import { ApplicationError } from '@/schemas';

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
export function useBranding(domainId: string) {
  const store = useBrandStore();
  const notifications = useNotificationsStore();
  const isLoading = ref(false);
  const isInitialized = ref(false);
  const error = ref<ApplicationError | null>(null);

  const brandSettings = ref<BrandSettings>(store.getSettings(domainId || ''));
  const originalSettings = ref<BrandSettings | null>(null);
  const logoImage = ref<ImageProps | null>(null);

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => (error.value = err),
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  const initialize = () =>
    wrap(async () => {
      if (!domainId) return;
      const settings = await store.fetchSettings(domainId);
      brandSettings.value = settings;
      originalSettings.value = { ...settings };
      logoImage.value = store.getLogo(domainId);
      isInitialized.value = true;
    });

  onMounted(initialize);

  const primaryColor = computed(() =>
    isInitialized.value ? brandSettings.value.primary_color : undefined
  );
  const hasUnsavedChanges = computed(() => {
    if (!originalSettings.value) return false;
    return !Object.entries(brandSettings.value).every(
      ([key, value]) => originalSettings.value?.[key as keyof BrandSettings] === value
    );
  });

  watch(
    () => primaryColor.value,
    (newColor) => {
      if (newColor) {
        brandSettings.value.button_text_light = shouldUseLightText(newColor);
      }
    }
  );

  const saveBranding = (updates: Partial<BrandSettings>) =>
    wrap(async () => {
      if (!domainId) return;
      const updated = await store.updateSettings(domainId, updates);
      brandSettings.value = updated;
      originalSettings.value = { ...brandSettings.value };
      notifications.show('Brand settings saved successfully', 'success');
    });

  const handleLogoUpload = async (file: File) =>
    wrap(async () => {
      await store.uploadLogo(domainId, file);
    });

  const removeLogo = async () =>
    wrap(async () => {
      await store.removeLogo(domainId);
    });

  return {
    isLoading,
    error,
    brandSettings,
    logoImage,
    primaryColor,
    hasUnsavedChanges,
    isInitialized,
    initialize,
    saveBranding,
    handleLogoUpload,
    removeLogo,
  };
}
