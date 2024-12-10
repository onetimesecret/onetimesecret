<script setup lang="ts">
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
import { onMounted, ref } from 'vue'
import { onBeforeRouteLeave } from 'vue-router'

import ColorPicker from '../common/ColorPicker.vue'
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

const isDirty = ref(false)
const originalValues = ref<BrandSettings | null>(null)

const updateBrandSetting = <K extends keyof BrandSettings>(
  key: K,
  value: BrandSettings[K]
) => {
  emit('update:modelValue', {
    ...props.modelValue,
    [key]: value,
  })
  setDirtyState()
}

const updateFontFamilyStyle = (value: string) => {
  updateBrandSetting('font_family', value as keyof typeof FontFamily)
}

const updateCornerStyle = (value: string) => {
  updateBrandSetting('corner_style', value as keyof typeof CornerStyle)
}

const setDirtyState = () => {
  if (!originalValues.value) return

  isDirty.value = true;
}

onMounted(() => {
  originalValues.value = { ...props.modelValue }
})

onBeforeRouteLeave((to, from, next) => {
  if (isDirty.value) {
    const answer = window.confirm('You have unsaved changes. Are you sure you want to leave?')
    if (answer) {
      next()
    } else {
      next(false)
    }
  } else {
    next()
  }
})

// Reset original values after successful save
const handleSubmit = () => {
  emit('submit')
  originalValues.value = { ...props.modelValue }
}

</script>

<template>
  <div class="border-b border-gray-200 bg-white/80 backdrop-blur-sm dark:border-gray-700 dark:bg-gray-800/80">
    <div class="mx-auto max-w-7xl px-4 py-3 sm:px-6 lg:px-8">
      <form
        @submit.prevent="handleSubmit"
        class="flex flex-wrap items-center gap-4">
        <input
          type="hidden"
          name="shrimp"
          :value="shrimp"
        />

        <!-- Color Picker -->

        <ColorPicker
          :model-value="modelValue.primary_color"
          name="brand[primary_color]"
          label="Brand Color"
          id="brand-color"
          @update:model-value="updateBrandSetting('primary_color', $event)"
        />


        <div class="inline-flex items-center gap-2">
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
        </div>

        <!-- Instructions Field -->

        <slot name="instructions-button"></slot>


        <!-- Spacer -->
        <div class="flex-1"></div>

        <!-- Save Button -->
        <button
          type="submit"
          :disabled="isSubmitting"
          class="inline-flex h-11 w-full items-center justify-center rounded-lg border border-transparent bg-brand-600 px-4 text-base font-medium text-white shadow-sm hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto sm:text-sm">
          <Icon
            v-if="isSubmitting"
            icon="mdi:loading"
            class="-ml-1 mr-2 size-4 animate-spin"
          />
          <Icon
            v-else
            icon="mdi:content-save"
            class="-ml-1 mr-2 size-4"
          />
          {{ isSubmitting ? 'Save' : 'Save' }}
        </button>
      </form>
    </div>
  </div>
</template>
