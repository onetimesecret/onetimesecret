<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
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
    light: 'ph-sun-bold',
    dark: 'ph-moon-bold',
    system: 'ph-desktop-bold',
    grid: 'ph-grid-four',
    list: 'ph-list-bold',
    compact: 'ph-corners-in-bold',
    comfortable: 'ph-arrows-out-bold',
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
  return props.iconMap[value] || 'material-symbols-question-mark';
});

const cycleValue = () => {
  const currentValue = props.modelValue ?? props.defaultValue;
  const currentIndex = props.options.indexOf(currentValue);
  const nextIndex = (currentIndex + 1) % props.options.length;
  emit('update:modelValue', props.options[nextIndex]);
};
</script>

<template>
  <button type="button"
          @click="cycleValue"
          class="focus:ring-primary-500 group relative inline-flex h-10 items-center gap-2 rounded-lg
                   bg-white px-4 shadow-sm ring-1
                   ring-gray-200 transition-all duration-200 ease-in-out
                   hover:bg-gray-50 focus:outline-none focus:ring-2
                   focus:ring-offset-2 dark:bg-gray-800 dark:ring-gray-700 dark:hover:bg-gray-700
                   dark:focus:ring-offset-gray-900"
          :aria-label="$t('current-label-modelvalue-click-to-cycle-through-options', [label, modelValue])">
    <!-- Icon for current value -->
    <div class="relative size-5 text-gray-700 dark:text-gray-200">
      <OIcon collection=""
             :name="getCurrentIcon"
             class="size-5 transition-all duration-200"
             :aria-hidden="true" />
    </div>

    <!-- Label tooltip on hover -->
    <div class="absolute -top-10 left-1/2 -translate-x-1/2 opacity-0
                transition-opacity duration-200 group-hover:opacity-100">
      <div class="flex flex-col items-center">
        <div class="min-w-[100px] rounded-md bg-gray-900 px-2 py-1 text-center text-xs text-white dark:bg-gray-700">
          <span class="ml-1">{{ displayValue }}</span>
        </div>
        <div class="-mb-1 mt-0.5 size-2 rotate-45 bg-gray-900 dark:bg-gray-700"></div>
      </div>
    </div>
  </button>
</template>
