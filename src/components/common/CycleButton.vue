<template>
  <button type="button"
        @click="cycleValue"
        class="group relative inline-flex items-center gap-2 rounded-lg px-4 h-11
         bg-white dark:bg-gray-800 hover:bg-gray-50 dark:hover:bg-gray-700
         shadow-sm ring-1 ring-gray-200 dark:ring-gray-700
         transition-all duration-200 ease-in-out
         focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2
         dark:focus:ring-offset-gray-900"
        :aria-label="`Current ${label}: ${modelValue}. Click to cycle through options.`">

    <!-- Icon for current value -->
    <div class="relative h-5 w-5 text-gray-700 dark:text-gray-200">
      <Icon :icon="getCurrentIcon"
            class="h-5 w-5 transition-all duration-200"
            :aria-hidden="true" />
    </div>

    <!-- Label tooltip on hover -->
    <div class="absolute -top-10 left-1/2 -translate-x-1/2 transform
                opacity-0 group-hover:opacity-100 transition-opacity duration-200">
      <div class="flex flex-col items-center">
        <div class="rounded-md bg-gray-900 dark:bg-gray-700 px-2 py-1 text-xs text-white min-w-[100px] text-center">
          <span class="ml-1">{{ displayValue }}</span>
        </div>
        <div class="h-2 w-2 rotate-45 transform bg-gray-900 dark:bg-gray-700
                    -mb-1 mt-0.5"></div>
      </div>
    </div>
  </button>
</template>

<script setup lang="ts">
import { Icon } from '@iconify/vue';
import { computed } from 'vue';

interface Props {
  modelValue: string | undefined;
  options: string[];
  label: string;
  displayMap?: Record<string, string>;
  iconMap?: Record<string, string>;
  defaultValue?: string;
}

const props = withDefaults(defineProps<Props>(), {
  displayMap: () => ({}),
  iconMap: () => ({
    // Default icons for common use cases
    light: 'ph:sun-bold',
    dark: 'ph:moon-bold',
    system: 'ph:desktop-bold',
    grid: 'ph:grid-four',
    list: 'ph:list-bold',
    compact: 'ph:corners-in-bold',
    comfortable: 'ph:arrows-out-bold',
  }),
  defaultValue: '',
});

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();

const displayValue = computed(() => {
  const value = props.modelValue ?? props.defaultValue;
  return props.displayMap[value] || value;
});

const getCurrentIcon = computed(() => {
  const value = props.modelValue ?? props.defaultValue;
  return props.iconMap[value] || 'ph:question-bold';
});

const cycleValue = () => {
  const currentValue = props.modelValue ?? props.defaultValue;
  const currentIndex = props.options.indexOf(currentValue);
  const nextIndex = (currentIndex + 1) % props.options.length;
  emit('update:modelValue', props.options[nextIndex]);
};
</script>
