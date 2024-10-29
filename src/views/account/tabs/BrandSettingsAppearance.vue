<template>
  <div class="space-y-6">
    <h3 class="text-lg font-medium text-gray-900 dark:text-gray-100">
      Appearance Settings
    </h3>

    <div class="space-y-6">
      <!-- Color Picker -->
      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Brand Color
        </label>
        <div class="flex items-center space-x-4">
          <div class="relative">
            <input
              type="color"
              v-model="localSettings.primary_color"
              class="w-12 h-12 rounded-lg cursor-pointer border-2 border-gray-200 dark:border-gray-600"
              aria-label="Choose brand color"
            >
          </div>
          <input
            type="text"
            v-model="localSettings.primary_color"
            class="flex-1 px-4 py-2 rounded-lg border border-gray-300 dark:border-gray-600 dark:bg-gray-700"
            aria-label="Color hex value"
          >
        </div>
      </div>

      <!-- Font Family -->
      <div>
        <label for="fontFamily" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Font Family
        </label>
        <select
          id="fontFamily"
          v-model="localSettings.font_family"
          class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 shadow-sm focus:border-brand-500 focus:ring-brand-500"
          :disabled="isSubmitting"
        >
          <option value="sans-serif">Sans Serif</option>
          <option value="serif">Serif</option>
          <option value="monospace">Monospace</option>
        </select>
      </div>

      <!-- Button Style -->
      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Button Style
        </label>
        <div class="grid grid-cols-3 gap-4">
          <button
            v-for="style in buttonStyles"
            :key="style.value"
            @click="localSettings.button_style = style.value"
            :class="[
              'p-4 border rounded-lg text-center',
              localSettings.button_style === style.value
                ? 'border-brand-500 ring-2 ring-brand-500'
                : 'border-gray-300 dark:border-gray-600'
            ]"
          >
            {{ style.label }}
          </button>
        </div>
      </div>
    </div>

    <!-- Save Button -->
    <div class="flex justify-end">
      <button
        @click="saveChanges"
        :disabled="isSubmitting"
        class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 disabled:opacity-50 disabled:cursor-not-allowed dark:focus:ring-offset-gray-800"
        aria-label="Save appearance settings"
      >
        <span v-if="isSubmitting">Saving...</span>
        <span v-else>Save Changes</span>
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import type { BrandSettings } from '@/types/onetime'

const props = defineProps<{
  brandSettings: BrandSettings
  isSubmitting: boolean
}>()

const emit = defineEmits<{
  (e: 'update:brandSettings', value: BrandSettings): void
}>()

const buttonStyles = [
  { value: 'rounded', label: 'Rounded' },
  { value: 'square', label: 'Square' },
  { value: 'pill', label: 'Pill' }
]

const localSettings = ref({ ...props.brandSettings })

watch(() => props.brandSettings, (newVal) => {
  localSettings.value = { ...newVal }
}, { deep: true })

const saveChanges = () => {
  emit('update:brandSettings', { ...localSettings.value })
}
</script>
