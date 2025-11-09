<!-- src/components/ctas/FancyIconLink.vue -->

<script setup lang="ts">
  import FancyIcon from '@/components/ctas/FancyIcon.vue';

  defineProps<{
    ariaLabel?: string;
    to: string;
    colonel?: boolean;
  }>();
</script>

<template>
  <div class="container">
    <div
      class="group ml-2 inline-flex items-center space-x-2 text-sm font-medium
        text-gray-700 transition-colors
        duration-150 ease-in-out hover:text-brand-500 focus:outline-none
        focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
        dark:text-gray-300 dark:hover:text-brand-400 dark:focus:ring-offset-gray-900">
      <FancyIcon />
    </div>
  </div>
</template>

<style scoped>
  @media (prefers-reduced-motion: reduce) {
    svg,
    svg * {
      animation: none !important;
    }
  }
</style>
