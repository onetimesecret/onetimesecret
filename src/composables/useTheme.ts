// composables/useTheme.ts

import { ref, watch } from 'vue';

const isDarkMode = ref(false);
const themeListeners = new Set<(isDark: boolean) => void>();
const isInitialized = ref(false);

export function useTheme() {

  const initializeTheme = () => {
    if (isInitialized.value) return;
    const storedPreference = localStorage.getItem('restMode');
    console.debug('storedPreference', storedPreference, isInitialized.value);
    isDarkMode.value =
      storedPreference !== null
        ? storedPreference === 'true'
        : window.matchMedia('(prefers-color-scheme: dark)').matches;

    updateDarkMode();
    isInitialized.value = true;
  };

  const onThemeChange = (callback: (isDark: boolean) => void) => {
    themeListeners.add(callback);
    return () => themeListeners.delete(callback);
  };

  const toggleDarkMode = () => {
    if (!isInitialized.value) {
      initializeTheme();
    }
    isDarkMode.value = !isDarkMode.value;
    updateDarkMode();
    themeListeners.forEach(listener => listener(isDarkMode.value));
  };

  const updateDarkMode = () => {
    localStorage.setItem('restMode', isDarkMode.value.toString());
    document.documentElement.classList.toggle('dark', isDarkMode.value);
  };

  function getThemeListenersSize() {
    return themeListeners.size;
  }

  watch(isDarkMode, updateDarkMode);

  return {
    isDarkMode,
    toggleDarkMode,
    initializeTheme,
    onThemeChange,
    isInitialized,
    getThemeListenersSize,
    clearThemeListeners: () => themeListeners.clear(),
  };
}
