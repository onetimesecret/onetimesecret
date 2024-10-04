<template>
  <div class="dark:bg-gray-800">
    <div v-if="error" class="rounded-md bg-red-50 dark:bg-red-900 p-4 mb-4">
      <div class="flex mb-8">
        <div class="flex-shrink-0">
          <Icon icon="mdi:fire-circle" class="h-5 w-5 text-red-400 dark:text-red-300" aria-hidden="true" />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-red-800 dark:text-red-100">Error</h3>
          <div class="mt-2 text-sm text-red-700 dark:text-red-200">
            <p>{{ error }}</p>
          </div>
        </div>
      </div>
    </div>

    <div v-if="success" class="rounded-md bg-green-50 dark:bg-green-900 p-4 mb-4">
      <div class="flex mb-8">
        <div class="flex-shrink-0">
          <Icon icon="mdi:check-circle" class="h-5 w-5 text-green-400 dark:text-green-300" aria-hidden="true" />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-green-800 dark:text-green-100">Success</h3>
          <div class="mt-2 text-sm text-green-700 dark:text-green-200">
            <p>{{ success }}</p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { Icon } from '@iconify/vue';

defineProps({
  success: String,
  error: String
});
</script>
