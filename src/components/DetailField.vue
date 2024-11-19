
<template>
  <div class="flex rounded-md bg-white dark:bg-gray-600">
    <div
      class="flex w-16 shrink-0 items-center justify-end border-r border-gray-200 bg-gray-100 px-3 py-2 dark:border-gray-500 dark:bg-gray-700"
      ref="labelContainerRef"
    >
      <span
        class="text-sm font-medium text-gray-500 dark:text-gray-300"
        ref="labelRef"
      >{{ label }}:</span>
    </div>
    <div class="flex grow items-center p-3">
      <div class="mr-2 min-w-0 grow">
        <span class="block truncate text-gray-800 dark:text-gray-200">
          {{ value }}<span
            v-if="appendix"
            class="text-gray-400"
          >{{ appendix }}</span>
        </span>
      </div>
      <div class="shrink-0">
        <CopyButton :text="value" />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import CopyButton from './CopyButton.vue';

interface Props {
  label: string;
  value: string;
  appendix?: string;
}

defineProps<Props>();

</script>
