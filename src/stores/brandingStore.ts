import { brandSettingschema } from '@/schemas/models/domain/brand';
import { defineStore } from 'pinia';
import { ref } from 'vue';

export const useBrandingStore = defineStore('branding', () => {
  const primaryColor = ref(brandSettingschema.shape.primary_color.parse(undefined));

  function setPrimaryColor(color: string) {
    primaryColor.value = brandSettingschema.shape.primary_color.parse(color);
  }

  return {
    primaryColor,
    setPrimaryColor,
  };
});
