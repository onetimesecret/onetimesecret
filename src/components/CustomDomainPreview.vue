<template>
  <SecretFormDrawer title="Link Preview" border="dashed" expandedBg="bg-gray-50 dark:bg-gray-700">
    <div class="mt-2 flex items-center space-x-2 overflow-hidden font-mono">
      <Icon icon="mdi:link-variant" class="text-gray-400 dark:text-gray-500 flex-shrink-0 transition-colors duration-200" />
      <div class="flex items-center space-x-1 overflow-hidden">
        <span class="text-sm text-gray-800 dark:text-gray-500 font-medium transition-colors duration-200">https://</span>
        <span class="text-sm text-slate-600 dark:text-slate-400 font-bold transition-colors duration-200">{{ props.default_domain }}</span>
        <span class="text-sm text-gray-600 dark:text-gray-400 truncate transition-colors duration-200">
          /secret/<span class="blur-sm">00000000000000000000000000</span>
        </span>
      </div>
    </div>
  </SecretFormDrawer>
</template>

<script setup lang="ts">
import { Icon } from '@iconify/vue';

import SecretFormDrawer from './secrets/form/SecretFormDrawer.vue';

const props = defineProps({
  default_domain: {
    type: String,
    required: false,
    default: window.site_host,
  }
});
</script>
