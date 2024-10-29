<template>
  <div
    v-if="show"
    class="fixed inset-0 bg-gray-900/50 dark:bg-gray-900/70 flex items-center justify-center"
    role="alert"
    aria-busy="true"
    :aria-label="message">
    <div class="bg-white dark:bg-gray-800 rounded-lg p-6 shadow-xl">
      <div
        class="animate-spin w-8 h-8 border-4 border-gray-300 dark:border-gray-600 border-t-blue-600 rounded-full"
        aria-hidden="true"></div>
      <p class="sr-only">{{ message }}</p>
    </div>
  </div>
</template>

<script setup lang="ts">
defineProps<{
  show: boolean;
  message?: string;
}>();
</script>
