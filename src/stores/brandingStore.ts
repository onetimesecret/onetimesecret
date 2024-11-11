import { defineStore } from 'pinia';
import { ref } from 'vue';

export const useBrandingStore = defineStore('branding', () => {
  const primaryColor = ref<string>('#dc4a22'); // Default color
  const isActive = ref<boolean>(false);        // Flag to activate color change

  function setPrimaryColor(color: string) {
    primaryColor.value = color;
  }

  function setActive(status: boolean) {
    isActive.value = status;
  }

  return {
    primaryColor,
    isActive,
    setPrimaryColor,
    setActive,
  };
});
