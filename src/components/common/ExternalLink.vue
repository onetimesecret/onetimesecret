<!-- components/common/ExternalLink.vue -->

<script setup lang="ts">
  defineProps<{
    href: string;
    label: string;
  }>();
</script>

<template>
  <a
    :href="href"
    target="_blank"
    rel="noopener noreferrer"
    class="flex items-center hover:text-gray-900 dark:hover:text-gray-200 transition-colors duration-200">
    <span class="mr-1">{{ label }}</span>
    <svg
      class="w-4 h-4"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor">
      <path
        d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6M15 3h6v6M10 14L21 3"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round" />
    </svg>
  </a>
</template>
