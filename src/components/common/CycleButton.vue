<!-- src/components/common/CycleButton.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { computed } from 'vue';

  import HoverTooltip from './HoverTooltip.vue';

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
  <div class="group relative">
    <HoverTooltip>{{ displayValue }}</HoverTooltip>
    <!-- prettier-ignore-attribute class -->
    <button
      type="button"
      @click="cycleValue"
      class="group relative inline-flex h-11 items-center gap-2
            rounded-lg bg-white px-4
            shadow-sm ring-1 ring-gray-200
            transition-all
            duration-200 hover:bg-gray-50 focus:outline-none focus:ring-2
            focus:ring-brand-500 focus:ring-offset-2 dark:bg-gray-800
            dark:ring-gray-700 dark:hover:bg-gray-700
            dark:focus:ring-brand-400 dark:focus:ring-offset-0"
      :aria-label="
        $t('current-label-modelvalue-click-to-cycle-through-options', [label, modelValue])
      ">
      <!-- Icon for current value -->
      <div class="relative size-5 text-gray-700 dark:text-gray-200">
        <OIcon
          collection=""
          :name="getCurrentIcon"
          class="size-5 transition-all duration-200"
          :aria-hidden="true"
        />
      </div>
    </button>
  </div>
</template>
