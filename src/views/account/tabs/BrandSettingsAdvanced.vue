<template>
  <div class="space-y-6">
    <h3 class="text-lg font-medium text-gray-900 dark:text-gray-100">
      Advanced Settings
    </h3>

    <div class="space-y-6">
      <!-- Custom CSS -->
      <div>
        <label for="customCss" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Custom CSS
        </label>
        <textarea
          id="customCss"
          v-model="localSettings.custom_css"
          rows="6"
          class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 shadow-sm focus:border-brand-500 focus:ring-brand-500 font-mono text-sm"
          :disabled="isSubmitting"
          aria-label="Enter custom CSS"
        ></textarea>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          Add custom CSS to further customize your brand appearance.
        </p>
      </div>

      <!-- Custom Header Scripts -->
      <div>
        <label for="headerScripts" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Header Scripts
        </label>
        <textarea
          id="headerScripts"
          v-model="localSettings.header_scripts"
          rows="4"
          class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 shadow-sm focus:border-brand-500 focus:ring-brand-500 font-mono text-sm"
          :disabled="isSubmitting"
          aria-label="Enter header scripts"
        ></textarea>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          Add custom scripts to be included in the page header.
        </p>
      </div>

      <!-- Analytics Integration -->
      <div>
        <label for="analyticsId" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
          Analytics ID
        </label>
        <input
          type="text"
          id="analyticsId"
          v-model="localSettings.analytics_id"
          class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 dark:bg-gray-700 shadow-sm focus:border-brand-500 focus:ring-brand-500"
          :disabled="isSubmitting"
          aria-label="Enter analytics ID"
        >
      </div>
    </div>

    <!-- Save Button -->
    <div class="flex justify-end">
      <button
        @click="saveChanges"
        :disabled="isSubmitting"
        class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 disabled:opacity-50 disabled:cursor-not-allowed dark:focus:ring-offset-gray-800"
        aria-label="Save advanced settings"
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

const localSettings = ref({ ...props.brandSettings })

watch(() => props.brandSettings, (newVal) => {
  localSettings.value = { ...newVal }
}, { deep: true })

const saveChanges = () => {
  emit('update:brandSettings', { ...localSettings.value })
}
</script>
