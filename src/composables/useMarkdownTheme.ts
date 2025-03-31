// src/composables/useMarkdownTheme.ts

import { useTheme } from '@/composables/useTheme';
import { ref, watchEffect } from 'vue';

export const useMarkdownTheme = () => {
  const theme = ref('atom-one-dark');
  const { isDarkMode } = useTheme();

  // Track active stylesheet element
  let activeStylesheet: HTMLLinkElement | null = null;

  const loadTheme = (themeName: string) => {
    // Remove previous theme if exists
    if (activeStylesheet) {
      activeStylesheet.remove();
    }

    // Create and append new stylesheet
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = `/highlight.js@11.8.0/styles/${themeName}.css`;
    document.head.appendChild(link);
    activeStylesheet = link;
  };

  watchEffect(() => {
    const newTheme = isDarkMode.value ? 'atom-one-dark' : 'atom-one-light';
    theme.value = newTheme;
    loadTheme(newTheme);
  });

  return {
    theme,
  };
};
