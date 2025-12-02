<!-- src/components/ui/ToastNotification.vue -->

<script setup lang="ts">
  defineProps<{
    show: boolean;
    message: string;
  }>();
</script>

<template>
  <div
    v-if="show"
    class="absolute right-3 top-3 rounded-md bg-gray-900 px-3 py-1.5 text-sm text-white shadow-lg transition-all duration-300 dark:bg-gray-700"
    :class="{
      'translate-y-1 opacity-0': !show,
      'translate-y-0 opacity-100': show,
    }">
    {{ message }}
  </div>
</template>
