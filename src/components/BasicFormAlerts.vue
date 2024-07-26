<template>
  <div class="mb-8">
    <div v-if="error" class="rounded-md bg-red-50 p-4 mb-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <Icon icon="mdi:xcircle" class="h-5 w-5 text-green-400" aria-hidden="true" />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-red-800">Error</h3>
          <div class="mt-2 text-sm text-red-700">
            <p>{{ error }}</p>
          </div>
        </div>
      </div>
    </div>

    <div v-if="success" class="rounded-md bg-green-50 p-4 mb-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <Icon icon="mdi:check-circle" class="h-5 w-5 text-green-400" aria-hidden="true" />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-green-800">Success</h3>
          <div class="mt-2 text-sm text-green-700">
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
