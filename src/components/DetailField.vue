<script setup lang="ts">
import CopyButton from './CopyButton.vue';

interface Props {
  label: string;
  value: string;
  appendix?: string;
}

defineProps<Props>();

</script>

<template>
  <div class="flex bg-white dark:bg-gray-600 rounded-md">
    <div class="w-16 flex-shrink-0 flex items-center justify-end px-3 py-2 bg-gray-100 dark:bg-gray-700 border-r border-gray-200 dark:border-gray-500" ref="labelContainerRef">
      <span class="text-sm font-medium text-gray-500 dark:text-gray-300" ref="labelRef">{{ label }}:</span>
    </div>
    <div class="flex-grow flex items-center p-3">
      <div class="flex-grow min-w-0 mr-2">
        <span class="text-gray-800 dark:text-gray-200 block truncate">
          {{ value }}<span v-if="appendix" class="text-gray-400">{{ appendix }}</span>
        </span>
      </div>
      <div class="flex-shrink-0">
        <CopyButton :text="value" />
      </div>
    </div>
  </div>
</template>


<style scoped>

</style>
