<template>
  <div class="bg-white/80 dark:bg-gray-800/80 backdrop-blur-sm border-b border-gray-200 dark:border-gray-700">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3">
      <form @submit.prevent="$emit('submit')" class="flex items-center gap-4">
        <input type="hidden" name="shrimp" :value="shrimp" />

        <!-- Color Picker -->
        <div class="w-48">
          <label id="color-picker-label" class="sr-only">Brand Color</label>
          <div class="group flex items-center bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-600 rounded-lg shadow-sm px-3 py-2">
            <div class="relative">
              <input
                type="color"
                :value="modelValue.primary_color"
                @input="updateColor"
                name="brand[primary_color]"
                class="w-8 h-8 rounded cursor-pointer border border-gray-200 dark:border-gray-600 focus:outline-none"
                aria-labelledby="color-picker-label">
              <div
                class="absolute -right-1 -top-1 w-3 h-3 rounded-full shadow-sm ring-2 ring-white dark:ring-gray-800"
                :style="{ backgroundColor: modelValue.primary_color }"
                aria-hidden="true"></div>
            </div>
            <input
              type="text"
              :value="modelValue.primary_color"
              @input="updateColor"
              name="brand[primary_color]"
              class="ml-3 w-24 bg-transparent border-none focus:ring-0 p-0 text-base font-medium text-gray-900 dark:text-gray-100 placeholder-gray-400 uppercase"
              pattern="^#[0-9A-Fa-f]{6}$"
              placeholder="#000000"
              maxlength="7"
              aria-label="Brand color hex value">
          </div>
        </div>

        <!-- Font Family -->
        <CycleButton
          :modelValue="modelValue.font_family"
          @update:modelValue="updateFont"
          :options="fontOptions"
          label=""
          :display-map="fontDisplayMap"
          :icon-map="fontIconMap" />

        <!-- Corner Style -->
        <CycleButton
          :modelValue="modelValue.corner_style"
          @update:modelValue="updateCornerStyle"
          :options="cornerStyleOptions"
          label="Corner Style"
          :display-map="cornerStyleDisplayMap"
          :icon-map="cornerStyleIconMap" />

        <!-- Spacer -->
        <div class="flex-1"></div>

        <slot name="instructions-button"></slot>

        <!-- Save Button -->
        <button
          type="submit"
          :disabled="isSubmitting"
          class="inline-flex items-center px-4 py-2 border border-transparent rounded-lg shadow-sm text-sm font-medium text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 disabled:opacity-50 disabled:cursor-not-allowed">
          <Icon
            v-if="isSubmitting"
            icon="mdi:loading"
            class="animate-spin -ml-1 mr-2 h-4 w-4" />
          <Icon
            v-else
            icon="mdi:content-save"
            class="-ml-1 mr-2 h-4 w-4" />
          {{ isSubmitting ? 'Saving...' : 'Save' }}
        </button>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import { Icon } from '@iconify/vue';
import type { BrandSettings } from 'types/onetime';
import CycleButton from '../common/CycleButton.vue';

const props = defineProps<{
  modelValue: BrandSettings;
  shrimp: string;
  isSubmitting: boolean;
}>();

const emit = defineEmits<{
  (e: 'update:modelValue', value: BrandSettings): void;
  (e: 'submit'): void;
}>();

const fontOptions = ['sans-serif', 'serif', 'monospace'];
const fontDisplayMap = {
  'sans-serif': 'Sans Serif',
  'serif': 'Serif',
  'monospace': 'Monospace'
};
const fontIconMap = {
  'sans-serif': 'ph:text-aa-bold',
  'serif': 'ph:text-t-bold',
  'monospace': 'ph:code-simple-bold'
};

const cornerStyleOptions = ['rounded', 'pill', 'square'];
const cornerStyleDisplayMap = {
  'rounded': 'Rounded',
  'pill': 'Pill Shape',
  'square': 'Square'
};
const cornerStyleIconMap = {
  'rounded': 'tabler:border-corner-rounded',
  'pill': 'tabler:border-corner-pill',
  'square': 'tabler:border-corner-square'
};

const updateColor = (event: Event) => {
  const value = (event.target as HTMLInputElement).value;
  emit('update:modelValue', { ...props.modelValue, primary_color: value });
};

const updateFont = (value: string) => {
  emit('update:modelValue', { ...props.modelValue, font_family: value });
};

const updateCornerStyle = (value: string) => {
  emit('update:modelValue', { ...props.modelValue, corner_style: value });
};
</script>
