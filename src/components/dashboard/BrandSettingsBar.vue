<script setup lang="ts">
import type { BrandSettings } from '@/schemas/models';
import {
  CornerStyle,
  cornerStyleDisplayMap,
  cornerStyleIconMap,
  cornerStyleOptions,
  fontDisplayMap,
  FontFamily,
  fontIconMap,
  fontOptions,
} from '@/schemas/models/domain/brand';
import { Icon } from '@iconify/vue'
import { computed } from 'vue'

import ColorPicker from '../common/ColorPicker.vue'
import CycleButton from '../common/CycleButton.vue'

const props = withDefaults(defineProps<{
  modelValue: BrandSettings;
  isLoading: boolean;
}>(), {
  modelValue: () => ({
    primary_color: '#000000',
    font_family: 'sans',
    corner_style: 'rounded',
    button_text_light: true,
    instructions_pre_reveal: '',
    instructions_post_reveal: '',
    instructions_reveal: ''
  }),
  isLoading: false
});

// Add emit definitions
const emit = defineEmits<{
  (e: 'update:modelValue', value: BrandSettings): void
  (e: 'submit'): void
}>()

const primaryColor = computed(() => props.modelValue?.primary_color || '#000000');

const updateBrandSetting = <K extends keyof BrandSettings>(
  key: K,
  value: BrandSettings[K]
) => {
  emit('update:modelValue', {
    ...props.modelValue,
    [key]: value,
  })
}

const updateFontFamilyStyle = (value: string) => {
  updateBrandSetting('font_family', value as keyof typeof FontFamily)
}

const updateCornerStyle = (value: string) => {
  updateBrandSetting('corner_style', value as keyof typeof CornerStyle)
}

const handleSubmit = () => {
  emit('submit')
}
</script>

<template>
  <div class="border-b border-gray-200 bg-white/80 backdrop-blur-sm dark:border-gray-700 dark:bg-gray-800/80">
    <div class="mx-auto max-w-7xl px-4 py-3 sm:px-6 lg:px-8">
      <form
        @submit.prevent="handleSubmit"
        class="flex flex-wrap items-center gap-4">

        <!-- Color Picker -->
        <ColorPicker
        :model-value="primaryColor"
          name="brand[primary_color]"
          label="Brand Color"
          id="brand-color"
          @update:model-value="updateBrandSetting('primary_color', $event)"
        />


        <div class="inline-flex items-center gap-2">
          <!-- Corner Style -->
          <CycleButton
            :model-value="modelValue.corner_style"
            :default-value="CornerStyle.ROUNDED"
            @update:model-value="updateCornerStyle"
            :options="cornerStyleOptions"
            label="Corner Style"
            :display-map="cornerStyleDisplayMap"
            :icon-map="cornerStyleIconMap"
          />

          <!-- Font Family -->
          <CycleButton
            :model-value="modelValue.font_family"
            :default-value="FontFamily.SANS"
            @update:model-value="updateFontFamilyStyle"
            :options="fontOptions"
            label="Font Family"
            :display-map="fontDisplayMap"
            :icon-map="fontIconMap"
          />
        </div>

        <!-- Instructions Field -->

        <slot name="instructions-button"></slot>


        <!-- Spacer -->
        <div class="flex-1"></div>

        <!-- Save Button -->
        <button
          type="submit"
          :disabled="isLoading"
          class="inline-flex h-11 w-full items-center justify-center rounded-lg border border-transparent bg-brand-600 px-4 text-base font-medium text-white shadow-sm hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto sm:text-sm">
          <Icon
            v-if="isLoading"
            icon="mdi:loading"
            class="-ml-1 mr-2 size-4 animate-spin"
          />
          <Icon
            v-else
            icon="mdi:content-save"
            class="-ml-1 mr-2 size-4"
          />
          {{ isLoading ? 'Save' : 'Save' }}
        </button>
      </form>
    </div>
  </div>
</template>
