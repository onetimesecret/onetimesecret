import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { inject, ref } from 'vue';
import type { BrandSettings, ImageProps } from '@/schemas/models';
import { responseSchemas } from '@/schemas/api';

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
};

/* eslint max-lines-per-function: off */
export const useBrandStore = defineStore('brand', () => {
  const $api = inject('api') as AxiosInstance;
  const settings = ref<Record<string, BrandSettings>>({});
  const logos = ref<Record<string, ImageProps>>({});
  const _initialized = ref(false);

  /* Reset primaryColor by passing undefined through primary_color field validator
   * This triggers Zod schema's default value if defined
   * schema.shape provides access to individual field validators
   * See https://zod.dev/ for schema parsing docs
   * See https://pinia.vuejs.org/core-concepts/state.html for Pinia state management
   */
  // primaryColor.value = brandSettingschema.shape.primary_color.parse(undefined);

  function init() {
    if (_initialized.value) return;
    _initialized.value = true;
  }

  async function fetchSettings(domainId: string) {
    const response = await $api.get(`/api/v2/domains/${domainId}/brand`);
    const validated = responseSchemas.brandSettings.parse(response.data);
    settings.value[domainId] = validated.record;
    return validated.record;
  }

  async function updateSettings(domainId: string, updates: Partial<BrandSettings>) {
    const formattedUpdates = {
      ...updates,
      primary_color: updates.primary_color?.toLowerCase(),
    };

    const response = await $api.put(`/api/v2/domains/${domainId}/brand`, {
      brand: formattedUpdates,
    });
    const validated = responseSchemas.brandSettings.parse(response.data);
    // Merge the response with existing settings instead of overwriting
    settings.value[domainId] = {
      ...settings.value[domainId],
      ...validated.record,
    };

    return settings.value[domainId];
  }

  async function fetchLogo(domainId: string) {
    const response = await $api.get(`/api/v2/domains/${domainId}/logo`);
    const validated = responseSchemas.imageProps.parse(response.data);
    logos.value[domainId] = validated.record;
    return validated.record;
  }

  async function uploadLogo(domainId: string, file: File) {
    const formData = new FormData();
    formData.append('image', file);
    const response = await $api.post(`/api/v2/domains/${domainId}/logo`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
    const validated = responseSchemas.imageProps.parse(response.data);
    logos.value[domainId] = validated.record;
    return validated.record;
  }

  async function removeLogo(domainId: string) {
    await $api.delete(`/api/v2/domains/${domainId}/logo`);
    delete logos.value[domainId];
  }

  function getSettings(domainId: string) {
    return {
      ...defaultBranding,
      ...settings.value[domainId],
    };
  }

  function getLogo(domainId: string) {
    return logos.value[domainId] || null;
  }

  return {
    init,
    fetchSettings,
    updateSettings,
    uploadLogo,
    removeLogo,
    getSettings,
    fetchLogo,
    getLogo,
  };
});

// function isEqual(a: BrandSettings, b: BrandSettings) {
//   const keys: (keyof BrandSettings)[] = [
//     'primary_color',
//     'font_family',
//     'corner_style',
//     'button_text_light',
//     'instructions_pre_reveal',
//     'instructions_post_reveal',
//     'instructions_reveal',
//     'allow_public_api',
//     'allow_public_homepage',
//   ];

//   return keys.every((key) => a[key] === b[key]);
// }
