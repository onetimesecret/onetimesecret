
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
  <div class="flex min-w-0">
    <div
    class="flex w-24 shrink-0 items-center justify-end border-r border-gray-200 bg-gray-100 px-3 py-2 dark:border-gray-500 dark:bg-gray-800/70"
      ref="labelContainerRef">
      <span
        class="truncate text-sm font-medium text-gray-500 dark:text-gray-300"
        ref="labelRef">{{ label }}:</span>
    </div>
    <div class="flex min-w-0 grow items-center p-3">
      <div class="mr-2 min-w-0 grow">
        <span class="block truncate text-gray-800 dark:text-gray-200">
          {{ value }}<span
            v-if="appendix"
            class="text-gray-400">{{ appendix }}</span>
        </span>
      </div>
      <div class="shrink-0">
        <CopyButton :text="value" />
      </div>
    </div>
  </div>
</template>
