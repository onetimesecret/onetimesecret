<template>
  <div class="mb-2 p-3 font-mono border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-lg">
    <h3 class="text-sm font-medium text-gray-500 dark:text-gray-400 mb-2 ">Link Preview</h3>
    <div class="flex items-center space-x-2 overflow-hidden">
      <Icon icon="mdi:link-variant"
            class="text-gray-400 dark:text-gray-500 flex-shrink-0" />
      <div class="flex items-center space-x-1 overflow-hidden">
        <span class="text-sm text-gray-800 dark:text-gray-500 font-medium">https://</span>
        <span class="text-sm text-slate-600 dark:text-slate-400 font-bold">{{ props.default_domain }}</span>
        <span class="text-sm text-gray-600 dark:text-gray-400 truncate">
          /secret/<span class="blur-sm">00000000000000000000000000</span>
        </span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { Icon } from '@iconify/vue';

const props = defineProps({
  default_domain: {
    type: String,
    required: false,
    default: window.site_host,
  }
});


</script>
