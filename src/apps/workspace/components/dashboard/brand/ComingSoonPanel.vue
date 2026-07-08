<!-- src/apps/workspace/components/dashboard/brand/ComingSoonPanel.vue -->

<script setup lang="ts">
  /**
   * Faded "coming soon" wrapper for a not-yet-built path panel (Match my site,
   * Advanced). Renders the slotted mockup dimmed + blurred + non-interactive,
   * with an overlay carrying a "Coming soon" pill, a title and a one-line blurb.
   *
   * The mockup is decorative only: `pointer-events-none` + `aria-hidden` keep it
   * out of the tab order and off assistive tech, so the panel reads as a single
   * informative teaser rather than a broken form.
   */
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  defineProps<{
    title: string;
    blurb: string;
  }>();
</script>

<template>
  <div
    class="relative overflow-hidden rounded-2xl border border-gray-200
      bg-white dark:border-gray-700 dark:bg-gray-800">
    <!-- Decorative faded mockup -->
    <div
      class="pointer-events-none opacity-40 blur-[1.5px] select-none"
      aria-hidden="true">
      <slot></slot>
    </div>

    <!-- Overlay -->
    <div
      class="absolute inset-0 flex flex-col items-center justify-center gap-2
        bg-white/50 p-6 text-center backdrop-blur-[1px] dark:bg-gray-800/50">
      <span
        class="inline-flex items-center gap-1.5 rounded-full border border-gray-200
          bg-gray-50 px-3 py-1 text-xs font-semibold tracking-wide text-gray-500
          uppercase dark:border-gray-600 dark:bg-gray-700 dark:text-gray-300">
        {{ t('web.branding.badge_coming_soon') }}
      </span>
      <div class="text-base font-bold text-gray-900 dark:text-gray-100">
        {{ title }}
      </div>
      <p class="max-w-xs text-sm leading-relaxed text-gray-500 dark:text-gray-400">
        {{ blurb }}
      </p>
    </div>
  </div>
</template>
