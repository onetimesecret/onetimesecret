<template>
  <div class="bg-white/80 dark:bg-gray-800/80 backdrop-blur-sm border-b border-gray-200 dark:border-gray-700">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3">
      <form @submit.prevent="$emit('submit')"
            class="flex flex-wrap items-center gap-4">
        <input type="hidden"
               name="shrimp"
               :value="shrimp" />

        <!-- Color Picker -->

          <ColorPicker :model-value="modelValue.primary_color"
                       name="brand[primary_color]"
                       label="Brand Color"
                       id="brand-color"
                       @update:model-value="updateBrandSetting('primary_color', $event)" />


        <div class="inline-flex items-center gap-2">
          <!-- Font Family -->
          <CycleButton :model-value="modelValue.font_family"
                       :default-value="FontFamily.SANS"
                       @update:modelValue="updateFont"
                       :options="fontOptions"
                       label="Font Family"
                       :display-map="fontDisplayMap"
                       :icon-map="fontIconMap" />

          <!-- Corner Style -->
          <CycleButton :model-value="modelValue.corner_style"
                       :default-value="CornerStyle.ROUNDED"
                       @update:modelValue="updateCornerStyle"
                       :options="cornerStyleOptions"
                       label="Corner Style"
                       :display-map="cornerStyleDisplayMap"
                       :icon-map="cornerStyleIconMap" />
        </div>

        <!-- Instructions Field -->

          <slot name="instructions-button"></slot>


        <!-- Spacer -->
        <div class="flex-1"></div>

        <!-- Save Button -->
        <button type="submit"
                :disabled="isSubmitting"
                class="w-full sm:w-auto inline-flex items-center justify-center px-4 h-11 border border-transparent rounded-lg shadow-sm text-base sm:text-sm font-medium text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 disabled:opacity-50 disabled:cursor-not-allowed">

          <Icon v-if="isSubmitting"
                icon="mdi:loading"
                class="animate-spin -ml-1 mr-2 h-4 w-4" />
          <Icon v-else
                icon="mdi:content-save"
                class="-ml-1 mr-2 h-4 w-4" />
          {{ isSubmitting ? 'Save' : 'Save' }}
        </button>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import ColorPicker from '@/components/common/ColorPicker.vue'
import type { BrandSettings } from '@/schemas/models'
import {
  CornerStyle,
  cornerStyleDisplayMap,
  cornerStyleIconMap,
  cornerStyleOptions,
  fontDisplayMap,
  FontFamily,
  fontIconMap,
  fontOptions,
} from '@/schemas/models/domain/brand'
import { Icon } from '@iconify/vue'

import CycleButton from '../common/CycleButton.vue'

const props = defineProps<{
  modelValue: BrandSettings
  shrimp: string
  isSubmitting: boolean
}>()

const emit = defineEmits<{
  (e: 'update:modelValue', value: BrandSettings): void
  (e: 'submit'): void
}>()

const updateBrandSetting = <K extends keyof BrandSettings>(
  key: K,
  value: BrandSettings[K]
) => {
  emit('update:modelValue', {
    ...props.modelValue,
    [key]: value,
  })
}

// Update font family
const updateFont = (value: string) => {
  updateBrandSetting('font_family', value as keyof typeof FontFamily)
}

// Update corner style
const updateCornerStyle = (value: string) => {
  updateBrandSetting('corner_style', value as keyof typeof CornerStyle)
}
</script>
