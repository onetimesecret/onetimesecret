<!-- src/components/ThemeToggle.vue -->

<script setup lang="ts">
  import { onMounted, onUnmounted } from 'vue';
  import { useTheme } from '@/composables/useTheme';
  import { useI18n } from 'vue-i18n';

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
    ? t('dark-mode-enabled')
    : t('light-mode-enabled');

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
    class="size-10 p-1 rounded-md text-gray-500 opacity-80 hover:opacity-100
    transition-colors hover:bg-gray-200 dark:text-gray-400 dark:hover:bg-gray-700
    inline-flex items-center justify-center"
    :title="isDarkMode ? $t('switch-to-light-mode') : $t('switch-to-dark-mode')"
    @keydown.enter="handleToggle"
    @keydown.space.prevent="handleToggle">
    <!-- Moon icon -->
    <svg
      v-if="isDarkMode"
      viewBox="0 0 24 24"
      fill="none"
      class="size-6"
      role="img"
      aria-hidden="true"
      focusable="false">
      <path
        fill-rule="evenodd"
        clip-rule="evenodd"
        d="M17.715 15.15A6.5 6.5 0 0 1 9 6.035C6.106 6.922 4 9.645 4 12.867c0 3.94 3.153 7.136 7.042 7.136 3.101 0 5.734-2.032 6.673-4.853Z"
        class="fill-transparent" />
      <path
        d="m17.715 15.15.95.316a1 1 0 0 0-1.445-1.185l.495.869ZM9 6.035l.846.534a1 1 0 0 0-1.14-1.49L9 6.035Zm8.221 8.246a5.47 5.47 0 0 1-2.72.718v2a7.47 7.47 0 0 0 3.71-.98l-.99-1.738Zm-2.72.718A5.5 5.5 0 0 1 9 9.5H7a7.5 7.5 0 0 0 7.5 7.5v-2ZM9 9.5c0-1.079.31-2.082.845-2.93L8.153 5.5A7.47 7.47 0 0 0 7 9.5h2Zm-4 3.368C5 10.089 6.815 7.75 9.292 6.99L8.706 5.08C5.397 6.094 3 9.201 3 12.867h2Zm6.042 6.136C7.718 19.003 5 16.268 5 12.867H3c0 4.48 3.588 8.136 8.042 8.136v-2Zm5.725-4.17c-.81 2.433-3.074 4.17-5.725 4.17v2c3.552 0 6.553-2.327 7.622-5.537l-1.897-.632Z"
        class="fill-slate-400 dark:fill-slate-500" />
      <path
        fill-rule="evenodd"
        clip-rule="evenodd"
        d="M17 3a1 1 0 0 1 1 1 2 2 0 0 0 2 2 1 1 0 1 1 0 2 2 2 0 0 0-2 2 1 1 0 1 1-2 0 2 2 0 0 0-2-2 1 1 0 1 1 0-2 2 2 0 0 0 2-2 1 1 0 0 1 1-1Z"
        class="fill-slate-400 dark:fill-slate-500" />
    </svg>
    <!-- Sun icon -->
    <svg
      v-else
      viewBox="0 0 24 24"
      fill="none"
      class="size-6"
      aria-hidden="true"
      role="img"
      focusable="false"
      stroke="currentColor"
      xmlns="http://www.w3.org/2000/svg">
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
    </svg>
  </button>
</template>
