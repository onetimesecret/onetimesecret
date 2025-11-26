<!-- src/components/common/LoadingOverlay.vue -->

<script setup lang="ts">
defineProps<{
  show: boolean;
  message?: string;
}>();
</script>

<template>
  <div
    v-if="show"
    class="fixed inset-0 flex items-center justify-center bg-gray-900/50 dark:bg-gray-900/70"
    role="alert"
    aria-busy="true"
    :aria-label="message">
    <div class="rounded-lg bg-white p-6 shadow-xl dark:bg-gray-800">
      <div
        class="size-8 animate-spin rounded-full border-4 border-gray-300 border-t-blue-600 dark:border-gray-600"
        aria-hidden="true"></div>
      <p class="sr-only">
        {{ message }}
      </p>
    </div>
  </div>
</template>
