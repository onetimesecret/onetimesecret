<template>
  <div class="space-y-9 my-16 max-w-full mx-auto px-4 sm:px-6 lg:px-8 dark:bg-gray-900">
    <BasicFormAlerts
      :success="success"
      :error="error"
    />

    <form @submit.prevent="submitForm" class="space-y-6">
      <input
        type="hidden"
        name="shrimp"
        :value="csrfStore.shrimp"
      />

      <DomainInput
        v-model="domain"
        :is-valid="true"
        domain=""
        autofocus
        required
        placeholder="e.g. secrets.example.com"
        class="dark:bg-gray-800 dark:text-white dark:border-gray-700"
      />

      <div class="flex flex-col-reverse sm:flex-row sm:space-x-4 space-y-4 space-y-reverse sm:space-y-0">
        <!-- Cancel/Back Button -->
        <button
          type="button"
          @click="$router.back()"
          class="w-full sm:w-1/2 inline-flex justify-center items-center
            px-4 py-2
            border border-gray-300 rounded-md shadow-sm
            text-base font-medium text-gray-700
            bg-white
            hover:bg-gray-50
            focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500
            dark:bg-gray-800 dark:border-gray-600 dark:text-gray-200
            dark:hover:bg-gray-700 dark:focus:ring-offset-gray-900"
          aria-label="Go back to previous page"
        >
          <svg
            class="mr-2 -ml-1 h-5 w-5"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            />
          </svg>
          Back
        </button>

        <!-- Submit Button -->
        <button
          type="submit"
          :disabled="isSubmitting"
          class="w-full sm:w-1/2 inline-flex justify-center items-center
            px-4 py-2
            border border-transparent rounded-md shadow-sm
            text-base font-medium text-white
            bg-brand-600
            hover:bg-brand-700
            focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500
            disabled:opacity-50 disabled:cursor-not-allowed
            dark:bg-brand-500 dark:hover:bg-brand-400
            dark:focus:ring-offset-gray-900"
          aria-live="polite"
        >
          <span v-if="isSubmitting" class="inline-flex items-center">
            <svg
              class="animate-spin -ml-1 mr-2 h-5 w-5 text-white"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                class="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                stroke-width="4"
              />
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              />
            </svg>
            Adding...
          </span>
          <span v-else>Continue</span>
        </button>
      </div>
    </form>
  </div>
</template>


<script setup lang="ts">
import { ref } from 'vue';
import BasicFormAlerts from './BasicFormAlerts.vue';
import DomainInput from './DomainInput.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import type { CustomDomainApiResponse } from '@/types';
import { useCsrfStore } from '@/stores/csrfStore';

const csrfStore = useCsrfStore();
const domain = ref('');
const emit = defineEmits(['domain-added']);

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: '/api/v2/account/domains/add',
  successMessage: 'Domain added successfully.',
  onSuccess: (data: CustomDomainApiResponse) => {
    console.log('Domain added:', data);
    domain.value = data.record.display_domain;
    if (!domain.value) {
      console.error('Domain is undefined or empty');
    }
    try {
      emit('domain-added', domain.value);
    } catch (error) {
      console.error('Error emitting domain-added event:', error);
    }
  },
  onError: (data: unknown) => {
    console.error('Error adding domain:', data);
  },
});
</script>
