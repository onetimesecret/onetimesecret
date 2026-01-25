<!-- src/shared/components/common/LanguageButton.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { computed } from 'vue';

import HoverTooltip from './HoverTooltip.vue';

const { t, availableLocales } = useI18n();

const props = defineProps<{
  modelValue: string;
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void;
}>();

// Map of locale codes to their display names
const localeDisplayMap: Record<string, string> = {
  en: 'English',
  es: 'Español',
  fr: 'Français',
  de: 'Deutsch',
  // Add other languages as needed
};

// Map of locale codes to their icons
const localeIconMap: Record<string, string> = {
  en: 'ph-flag-bold',
  es: 'ph-flag-bold',
  fr: 'ph-flag-bold',
  de: 'ph-flag-bold',
  // Add other languages as needed
};

const displayValue = computed(() =>
  localeDisplayMap[props.modelValue] || props.modelValue
);

const getCurrentIcon = computed(() =>
  localeIconMap[props.modelValue] || 'ph-translate-bold'
);

const cycleValue = () => {
  const currentIndex = availableLocales.indexOf(props.modelValue);
  const nextIndex = (currentIndex + 1) % availableLocales.length;
  emit('update:modelValue', availableLocales[nextIndex]);
};
</script>

<template>
  <div class="group relative">
    <HoverTooltip>{{ t('web.COMMON.language') }}</HoverTooltip>
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
      :aria-label="t('web.branding.current_label_modelvalue_click_to_cycle_through_options', [displayValue])">
      <div class="relative size-5 text-gray-700 dark:text-gray-200">
        {{ modelValue }}
        <OIcon
          collection=""
          :name="getCurrentIcon"
          class="size-5 transition-all duration-200"
          :aria-hidden="true" />
      </div>
    </button>
  </div>
</template>
