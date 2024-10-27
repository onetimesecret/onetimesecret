<template>
  <form @submit.prevent="submitForm">
    <input type="hidden"
           name="shrimp"
           :value="csrfStore.shrimp" />

    <!-- Add hidden input for primary_color since it's managed in parent -->
    <input type="hidden"
           name="brand[primary_color]"
           :value="brandSettings.primary_color" />

    <BasicFormAlerts :success="success"
                     :error="error" />

    <!-- Description -->
    <div class="space-y-2">
      <label for="description"
             class="block text-sm font-medium text-gray-700 dark:text-gray-200">
        Description
      </label>
      <textarea id="description"
                v-model="formData.description"
                name="brand[description]"
                rows="3"
                class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                placeholder="Enter a brief description of your brand"></textarea>
    </div>

    <!-- Font Family -->
    <div class="space-y-2">
      <label for="font_family"
             class="block text-sm font-medium text-gray-700 dark:text-gray-200">
        Font Family
      </label>
      <select id="font_family"
              v-model="formData.font_family"
              name="brand[font_family]"
              class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white">
        <option value="">Select a font family</option>
        <option value="sans-serif">Sans-serif</option>
        <option value="serif">Serif</option>
        <option value="monospace">Monospace</option>
      </select>
    </div>

    <!-- Button Style -->
    <div class="space-y-2">
      <label for="button_style"
             class="block text-sm font-medium text-gray-700 dark:text-gray-200">
        Button Style
      </label>
      <select id="button_style"
              v-model="formData.button_style"
              name="brand[button_style]"
              class="mt-1 block w-full rounded-lg border-gray-300 shadow-sm focus:border-brand-300 focus:ring focus:ring-brand-200 focus:ring-opacity-50 dark:bg-gray-700 dark:border-gray-600 dark:text-white">
        <option value="">Select a button style</option>
        <option value="rounded">Rounded</option>
        <option value="square">Square</option>
        <option value="pill">Pill</option>
      </select>
    </div>

    <!-- Submit Button -->
    <div class="pt-6">
      <button type="submit"
              :disabled="isSubmitting"
              class="w-full inline-flex justify-center py-3 px-4 border border-transparent shadow-sm text-sm font-medium rounded-lg text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:bg-brand-500 dark:hover:bg-brand-600 transition-colors duration-200 ease-in-out disabled:opacity-50 disabled:cursor-not-allowed">
        <span v-if="isSubmitting"
              class="mr-2">
          <svg class="animate-spin h-5 w-5 text-white"
               xmlns="http://www.w3.org/2000/svg"
               fill="none"
               viewBox="0 0 24 24">
            <circle class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"></circle>
            <path class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z">
            </path>
          </svg>
        </span>
        {{ isSubmitting ? 'Saving...' : 'Save Settings' }}
      </button>
    </div>
  </form>
</template>

<!-- AccountDomainBrandForm.vue -->
<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import { useCsrfStore } from '@/stores/csrfStore';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { BrandSettings } from '@/types/onetime';
import { computed } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
const domainId = route.params.domain as string;
const csrfStore = useCsrfStore();

const props = defineProps<{
  brandSettings: BrandSettings;
  isLoading: boolean;
}>();

const emit = defineEmits<{
  (e: 'update:brandSettings', value: BrandSettings): void;
}>();

// Use computed instead of watch + ref
const formData = computed({
  get: () => props.brandSettings,
  set: (newValue) => emit('update:brandSettings', newValue)
});

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: `/api/v2/account/domains/${domainId}/brand`,
  successMessage: 'Brand settings saved successfully',
  onSuccess: (response) => {
    if (response.data?.record?.brand) {
      emit('update:brandSettings', response.data.record.brand);
    } else {
      // Fallback to local data if response structure is unexpected
      emit('update:brandSettings', formData.value);
    }
  },
  onError: (err) => {
    console.error('Error saving brand settings:', err);
  },
});

</script>
