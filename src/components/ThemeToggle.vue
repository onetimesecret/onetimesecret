<!-- src/components/ThemeToggle.vue -->

<script setup lang="ts">
  import { onMounted, onUnmounted } from 'vue';
  import { useTheme } from '@/composables/useTheme';
  import { useI18n } from 'vue-i18n';
  import OIcon from './icons/OIcon.vue';

  const { t } = useI18n();

  const emit = defineEmits<{
    (e: 'theme-changed', isDark: boolean): void;
  }>();

  const { isDarkMode, toggleDarkMode, initializeTheme, clearThemeListeners } = useTheme();

  const handleToggle = () => {
    toggleDarkMode();
    emit('theme-changed', isDarkMode.value);

    // Announce theme change to screen readers
    const liveRegion = document.createElement('div');
    liveRegion.setAttribute('role', 'status');
    liveRegion.setAttribute('aria-live', 'polite');
    liveRegion.className = 'sr-only';
    liveRegion.textContent = isDarkMode.value
      ? t('blank-mode-enabled', ['dark'])
      : t('blank-mode-enabled', ['light']);

    document.body.appendChild(liveRegion);
    setTimeout(() => document.body.removeChild(liveRegion), 1000);
  };

  onMounted(initializeTheme);
  onUnmounted(clearThemeListeners);
</script>

<template>
  <button
    @click="handleToggle"
    :aria-label="$t('toggle-dark-mode')"
    :aria-pressed="isDarkMode"
    class="inline-flex items-center justify-center
          size-10 p-1 rounded-md transition-colors
          text-gray-700 dark:text-gray-100
          bg-inherit
          hover:bg-gray-200 hover:text-gray-900 dark:hover:bg-gray-700
          focus:outline-none focus:ring-2 focus:ring-brand-500
          focus:ring-offset-2 focus:ring-offset-white dark:ring-offset-gray-900
          dark:focus:ring-brand-400 dark:focus:ring-offset-gray-900"
    :title="isDarkMode ? $t('switch-to-blank-mode', ['light']) : $t('switch-to-blank-mode', ['dark'])"
    @keydown.enter="handleToggle"
    @keydown.space.prevent="handleToggle">
    <!-- Moon icon -->
    <OIcon
    v-if="isDarkMode"
      class="size-5"
      collection="ph"
      name="moon"
      aria-hidden="true" />
    <!-- Sun icon -->
    <OIcon
      v-else
      class="size-5"
      collection="ph"
      name="sun"
      aria-hidden="true" />
  </button>
</template>
