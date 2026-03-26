// src/shared/stores/brandStore.ts

import { responseSchemas } from '@/schemas/api/v3/responses';
import type { BrandSettings, ImageProps } from '@/schemas/shapes/v3/custom-domain';
import { gracefulParse } from '@/utils/schemaValidation';
import { useApi } from '@/shared/composables/useApi';
import { defineStore } from 'pinia';
import { ref } from 'vue';

const defaultBranding: BrandSettings = {
  primary_color: '#dc4a22',
  font_family: 'sans',
  corner_style: 'rounded',
  button_text_light: true,
  instructions_pre_reveal: '',
  instructions_post_reveal: '',
  instructions_reveal: '',
  allow_public_api: false,
  allow_public_homepage: false,
  passphrase_required: false,
  notify_enabled: false,
};

/* eslint max-lines-per-function: off */
export const useBrandStore = defineStore('brand', () => {
  const $api = useApi();
  const settings = ref<Record<string, BrandSettings>>({});
  const logos = ref<Record<string, ImageProps>>({});
  const _initialized = ref(false);

  function init() {
    if (_initialized.value) return;
    _initialized.value = true;
  }

  async function fetchSettings(domainId: string): Promise<BrandSettings> {
    const response = await $api.get(`/api/domains/${domainId}/brand`);
    const result = gracefulParse(responseSchemas.brandSettings, response.data, 'BrandSettingsResponse');
    if (!result.ok) {
      settings.value[domainId] = { ...defaultBranding };
      return settings.value[domainId];
    }
    settings.value[domainId] = result.data.record;
    return result.data.record;
  }

  async function updateSettings(domainId: string, updates: Partial<BrandSettings>) {
    const formattedUpdates = {
      ...updates,
      primary_color: updates.primary_color?.toLowerCase(),
    };

    const response = await $api.put(`/api/domains/${domainId}/brand`, {
      brand: formattedUpdates,
    });
    const result = gracefulParse(responseSchemas.brandSettings, response.data, 'BrandSettingsResponse');
    if (!result.ok) {
      throw new Error('Unable to update brand settings. Please try again.');
    }
    // Merge the response with existing settings instead of overwriting
    settings.value[domainId] = {
      ...settings.value[domainId],
      ...result.data.record,
    };

    return settings.value[domainId];
  }

  async function fetchLogo(domainId: string) {
    const response = await $api.get(`/api/domains/${domainId}/logo`);
    const result = gracefulParse(responseSchemas.imageProps, response.data, 'ImagePropsResponse');
    if (!result.ok) {
      delete logos.value[domainId];
      return null;
    }
    logos.value[domainId] = result.data.record;
    return result.data.record;
  }

  async function uploadLogo(domainId: string, file: File) {
    const formData = new FormData();
    formData.append('image', file);
    // Don't set Content-Type manually - Axios sets it with the correct boundary
    const response = await $api.post(`/api/domains/${domainId}/logo`, formData);
    const result = gracefulParse(responseSchemas.imageProps, response.data, 'ImagePropsResponse');
    if (!result.ok) {
      throw new Error('Unable to upload logo. Please try again.');
    }
    logos.value[domainId] = result.data.record;
    return result.data.record;
  }

  async function removeLogo(domainId: string) {
    await $api.delete(`/api/domains/${domainId}/logo`);
    delete logos.value[domainId];
  }

  function getSettings(domainId: string): BrandSettings {
    return {
      ...defaultBranding,
      ...settings.value[domainId],
    };
  }

  function getLogo(domainId: string): ImageProps | null {
    return logos.value[domainId] || null;
  }

  function compareSettings(domainId: string, newSettings: BrandSettings) {
    return isEqual(settings.value[domainId], newSettings);
  }

  return {
    init,
    fetchSettings,
    updateSettings,
    compareSettings,
    uploadLogo,
    removeLogo,
    getSettings,
    fetchLogo,
    getLogo,
  };
});

function isEqual(a: BrandSettings, b: BrandSettings): boolean {
  const keys: (keyof BrandSettings)[] = [
    'primary_color',
    'font_family',
    'corner_style',
    'button_text_light',
    'instructions_pre_reveal',
    'instructions_post_reveal',
    'instructions_reveal',
    'allow_public_api',
    'allow_public_homepage',
    'passphrase_required',
    'notify_enabled',
  ];

  return keys.every((key) => a[key] === b[key]);
}
