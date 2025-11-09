<!-- src/components/common/CycleButton.vue -->

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

const displayValue = computed(() => props.displayMap[props.modelValue] || props.modelValue);

const cycleValue = () => {
  const currentIndex = props.options.indexOf(props.modelValue);
  const nextIndex = (currentIndex + 1) % props.options.length;
  emit('update:modelValue', props.options[nextIndex]);
};
</script>

<template>
  <button
    type="button"
    @click="cycleValue"
    class="focus:ring-primary-500 rounded-lg border border-gray-200 bg-white px-4 py-2
           shadow-sm transition-colors duration-200 hover:bg-gray-50
           focus:outline-none focus:ring-2 focus:ring-offset-2 dark:border-gray-600
           dark:bg-gray-700 dark:hover:bg-gray-600"
    :aria-label="$t('current-label-modelvalue-click-to-cycle-through-options', [label, modelValue])">
    <span class="text-sm text-gray-500 dark:text-gray-400">{{ label }}</span>
    <span class="block text-base font-medium text-gray-900 dark:text-gray-100">
      {{ displayValue }}
    </span>
  </button>
</template>
