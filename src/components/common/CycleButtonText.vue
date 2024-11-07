<!-- src/components/common/CycleButton.vue -->
<template>
  <button
    type="button"
    @click="cycleValue"
    class="px-4 py-2 bg-white dark:bg-gray-700 border border-gray-200 dark:border-gray-600
           rounded-lg shadow-sm hover:bg-gray-50 dark:hover:bg-gray-600
           focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500
           transition-colors duration-200"
    :aria-label="`Current ${label}: ${modelValue}. Click to cycle through options.`"
  >
    <span class="text-sm text-gray-500 dark:text-gray-400">{{ label }}</span>
    <span class="block text-base font-medium text-gray-900 dark:text-gray-100">
      {{ displayValue }}
    </span>
  </button>
</template>

<script setup lang="ts">
import { computed } from 'vue';

interface Props {
  modelValue: string;
  options: string[];
  label: string;
  displayMap?: Record<string, string>;
}

const props = withDefaults(defineProps<Props>(), {
  displayMap: () => ({})
});

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();

const displayValue = computed(() => {
  return props.displayMap[props.modelValue] || props.modelValue;
});

const cycleValue = () => {
  const currentIndex = props.options.indexOf(props.modelValue);
  const nextIndex = (currentIndex + 1) % props.options.length;
  emit('update:modelValue', props.options[nextIndex]);
};
</script>
