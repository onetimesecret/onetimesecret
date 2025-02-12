// src/composables/useBranding.ts

import { ImageProps, type BrandSettings } from '@/schemas/models';
import { useNotificationsStore } from '@/stores';
import { useBrandStore } from '@/stores/brandStore';
import { shouldUseLightText } from '@/utils';
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { createI18nInstance } from '@/i18n';

import { AsyncHandlerOptions, useAsyncHandler, createError } from './useAsyncHandler';
import { ApplicationError } from '@/schemas';
import { AxiosError } from 'axios';

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
  const store = useBrandStore();
  const notifications = useNotificationsStore();
  const isLoading = ref(false);
  const isInitialized = ref(false);
  const error = ref<ApplicationError | null>(null);

  const { composer, setLocale } = createI18nInstance();
  const brandSettings = ref<BrandSettings>(store.getSettings(domainId || ''));
  const originalSettings = ref<BrandSettings | null>(null);
  const logoImage = ref<ImageProps | null>(null);

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => {
      const router = useRouter();
      if (err.code === 404 || err.code === 422 || err.code === 403) {
        return router.push({ name: 'NotFound' });
      }

      if ((err as ApplicationError).code !== 404) {
        throw err;
      }
      error.value = err;
    },
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  const initialize = () => {
    const router = useRouter();
    wrap(async () => {
      if (!domainId) return;
      const settings = await store.fetchSettings(domainId);

      if (!settings) {
        // Redirect to 404 if settings not found
        return router.push('NotFound');
      }

      // Set locale immediately after getting settings
      if (settings.locale) {
        console.debug('[useBranding] Setting locale:', settings.locale, settings);
        await setLocale(settings.locale);
      }

      // Quietly handle 404 errors for logo fetch
      try {
        const logo = await store.fetchLogo(domainId); // Assuming this is async
        logoImage.value = logo;
      } catch (err) {
        console.log(err);
        if ((err as AxiosError).status !== 404) {
          throw err;
        }
      }

      brandSettings.value = settings;
      originalSettings.value = { ...settings };
      isInitialized.value = true;
    });
  };
  const displayLocale = computed(() => brandSettings.value.locale);
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

  watch(
    () => brandSettings.value?.locale,
    async (newLocale) => {
      if (!newLocale) return;
      await setLocale(newLocale); // This updates the preview i18n instance
    },
    { immediate: true } // Add immediate to handle initial locale
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
      if (!domainId) throw createError('Domain ID is required to upload logo', 'human', 'error');
      const uploadedLogo = await store.uploadLogo(domainId, file);
      // Update local state with new logo
      logoImage.value = uploadedLogo;
    });

  const removeLogo = async () =>
    wrap(async () => {
      if (!domainId) throw createError('Domain ID is required to remove logo', 'human', 'error');
      await store.removeLogo(domainId);
      // Clear local logo state
      logoImage.value = null;
    });

  return {
    isLoading,
    error,
    brandSettings,
    logoImage,
    previewI18n: composer,
    displayLocale,
    primaryColor,
    hasUnsavedChanges,
    isInitialized,
    initialize,
    saveBranding,
    handleLogoUpload,
    removeLogo,
  };
}
