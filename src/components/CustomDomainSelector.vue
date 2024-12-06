<script setup>
import { Icon } from '@iconify/vue';
import { ref } from 'vue';


const props = defineProps({
  default_domain: {
    type: String,
    required: false,
    default: window.site_host,
  }
});

const emit = defineEmits(['select']);

const isSelected = ref(false);

const selectDomain = () => {
  isSelected.value = !isSelected.value;
  emit('select', props.site_host);
};
</script>

<template>
  <div
    class="flex cursor-pointer items-center space-x-2 overflow-hidden rounded-lg p-2 transition-colors duration-200 hover:bg-gray-100 dark:hover:bg-gray-700"
    :class="{ 'bg-gray-200 dark:bg-gray-600': isSelected }"
    @click="selectDomain">
    <!--<Icon icon="mdi:link-variant" class="text-gray-400 dark:text-gray-500 flex-shrink-0" />-->
    <div class="flex items-center space-x-1 overflow-hidden">
      <span class="text-sm font-medium text-gray-800 dark:text-gray-500">https://</span>
      <span class="text-sm font-bold text-brandcomp-600 dark:text-brandcomp-400">{{ props.default_domain }}</span>
      <span class="truncate font-mono text-sm text-gray-600 dark:text-gray-400">
        /secret/4keegbusj08ehpz5fj3rgqdn56you1c
      </span>
    </div>
    <Icon
      :icon="isSelected ? 'mdi:check-circle' : 'mdi:circle-outline'"
      class="ml-auto shrink-0 text-brandcomp-600 dark:text-brandcomp-400"
    />
  </div>
</template>
