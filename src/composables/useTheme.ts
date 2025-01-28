// composables/useTheme.ts

import { ref, watch } from 'vue';

const isDarkMode = ref(false);
const themeListeners = new Set<(isDark: boolean) => void>();

export function useTheme() {
  const onThemeChange = (callback: (isDark: boolean) => void) => {
    themeListeners.add(callback);
    return () => themeListeners.delete(callback);
  };

  const toggleDarkMode = () => {
    isDarkMode.value = !isDarkMode.value;
    localStorage.setItem('restMode', isDarkMode.value.toString());
    updateDarkMode();
  };

  const updateDarkMode = () => {
    document.documentElement.classList.toggle('dark', isDarkMode.value);
  };

  const initializeTheme = () => {
    const storedPreference = localStorage.getItem('restMode');
    isDarkMode.value =
      storedPreference !== null
        ? storedPreference === 'true'
        : window.matchMedia('(prefers-color-scheme: dark)').matches;
    updateDarkMode();
  };

  watch(isDarkMode, updateDarkMode);

  return {
    isDarkMode,
    toggleDarkMode,
    initializeTheme,
    onThemeChange,
  };
}
