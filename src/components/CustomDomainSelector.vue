<template>
  <div
    class="flex items-center space-x-2 overflow-hidden p-2 rounded-lg cursor-pointer hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors duration-200"
    :class="{ 'bg-gray-200 dark:bg-gray-600': isSelected }"
    @click="selectDomain"
  >
    <Icon icon="mdi:link-variant" class="text-gray-400 dark:text-gray-500 flex-shrink-0" />
    <div class="flex items-center space-x-1 overflow-hidden">
      <span class="text-sm text-gray-800 dark:text-gray-500 font-medium">https://</span>
      <span class="text-sm text-brandcomp-600 dark:text-brandcomp-400 font-bold">{{ props.default_domain }}</span>
      <span class="text-sm text-gray-600 dark:text-gray-400 font-mono truncate">
        /secret/4keegbusj08ehpz5fj3rgqdn56you1c
      </span>
    </div>
    <Icon
      :icon="isSelected ? 'mdi:check-circle' : 'mdi:circle-outline'"
      class="text-brandcomp-600 dark:text-brandcomp-400 ml-auto flex-shrink-0"
    />
  </div>
</template>

<script setup>
import { ref } from 'vue';
import { Icon } from '@iconify/vue';


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
