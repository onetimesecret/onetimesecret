// src/shared/composables/useBranding.ts

import { createI18nInstance } from '@/i18n';
import { ApplicationError } from '@/schemas';
import { ImageProps, type BrandSettings } from '@/schemas/models';
import { useNotificationsStore } from '@/shared/stores';
import { useBrandStore } from '@/shared/stores/brandStore';
import { useDomainsStore } from '@/shared/stores/domainsStore';
import { shouldUseLightText } from '@/utils';
import { AxiosError } from 'axios';
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';

import { AsyncHandlerOptions, useAsyncHandler, createError } from './useAsyncHandler';

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
  const domainsStore = useDomainsStore();
  const notifications = useNotificationsStore();
  const router = useRouter(); // Must be called at setup time, not in callbacks
  const isLoading = ref(false);
  const isInitialized = ref(false);
  const error = ref<ApplicationError | null>(null);

  const { composer, setLocale } = createI18nInstance();
  const brandSettings = ref<BrandSettings>(store.getSettings(domainId || ''));
  const originalSettings = ref<BrandSettings | null>(null);
  const logoImage = ref<ImageProps | null>(null);

  /**
   * Resolve extid from display_domain using domains store.
   * API endpoints require extid (e.g., "cd1234abc") not display_domain (e.g., "custom.example.com").
   * @param displayDomain - The display domain to look up
   * @returns The extid for API calls, or undefined if not found
   */
  const resolveExtid = (displayDomain: string): string | undefined => {
    const domain = domainsStore.domains?.find((d) => d.display_domain === displayDomain);
    return domain?.extid;
  };

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity, 'top'),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => {
      // Only redirect to NotFound for actual "not found" or "forbidden" errors
      // 422 is a validation error - show the message, don't navigate away
      if (err.code === 404 || err.code === 403) {
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
    wrap(async () => {
      if (!domainId) return;

      // Resolve extid from display_domain for API calls
      const extid = resolveExtid(domainId);
      if (!extid) {
        console.warn('[useBranding] Could not resolve extid for domain:', domainId);
        return;
      }

      const settings = await store.fetchSettings(extid);

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
        const logo = await store.fetchLogo(extid);
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

  /**
   * Save branding updates for a domain.
   * @param updates - Partial brand settings to update
   * @param targetDomain - Optional display domain override (for use when composable
   *                       is called at setup time but needs to save to different domains)
   */
  const saveBranding = (updates: Partial<BrandSettings>, targetDomain?: string) =>
    wrap(async () => {
      const effectiveDomain = targetDomain || domainId;
      if (!effectiveDomain) return;

      // Resolve extid from display_domain for API calls
      const extid = resolveExtid(effectiveDomain);
      if (!extid) {
        console.warn('[useBranding] Could not resolve extid for domain:', effectiveDomain);
        return;
      }

      const updated = await store.updateSettings(extid, updates);
      // Only update local state if we're saving to the composable's domain
      if (!targetDomain || targetDomain === domainId) {
        brandSettings.value = updated;
        originalSettings.value = { ...brandSettings.value };
      }
      notifications.show('Brand settings saved successfully', 'success', 'top');
    });

  const handleLogoUpload = async (file: File) =>
    wrap(async () => {
      if (!domainId) throw createError('Domain is required to upload logo', 'human', 'error');
      const extid = resolveExtid(domainId);
      if (!extid) throw createError('Could not resolve domain for logo upload', 'human', 'error');
      const uploadedLogo = await store.uploadLogo(extid, file);
      // Update local state with new logo
      logoImage.value = uploadedLogo;
    });

  const removeLogo = async () =>
    wrap(async () => {
      if (!domainId) throw createError('Domain is required to remove logo', 'human', 'error');
      const extid = resolveExtid(domainId);
      if (!extid) throw createError('Could not resolve domain for logo removal', 'human', 'error');
      await store.removeLogo(extid);
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
