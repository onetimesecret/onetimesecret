<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { WindowService } from '@/services/window.service';
import SecretFormDrawer from './secrets/form/SecretFormDrawer.vue';

const props = defineProps({
  default_domain: {
    type: String,
    required: false,
    default: WindowService.get('site_host'),
  }
});
</script>

<template>
  <SecretFormDrawer
    title="$t('link-preview')"
    border="dashed"
    expanded-bg="bg-gray-50 dark:bg-gray-700">
    <div class="mt-2 flex items-center space-x-2 overflow-hidden font-mono">
      <OIcon
        collection="mdi"
        name="link-variant"
        class="shrink-0 size-5 text-gray-400 transition-colors duration-200 dark:text-gray-500"
      />
      <div class="flex items-center space-x-1 overflow-hidden">
        <span class="text-sm font-medium text-gray-800 transition-colors duration-200 dark:text-gray-500">https://</span>
        <span class="text-sm font-bold text-slate-600 transition-colors duration-200 dark:text-slate-400">{{ props.default_domain }}</span>
        <span class="truncate text-sm text-gray-600 transition-colors duration-200 dark:text-gray-400">
          /secret/<span class="blur-sm">00000000000000000000000000</span>
        </span>
      </div>
    </div>
  </SecretFormDrawer>
</template>
