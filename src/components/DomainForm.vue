<template>
  <div class="space-y-9 my-16 dark:bg-gray-900">

    <BasicFormAlerts :success="success" :error="error" />

    <form @submit.prevent="submitForm" class="space-y-6">
      <input type="hidden"
             name="shrimp"
             :value="shrimp" />

      <DomainInput v-model="domain"
                   :is-valid="true"
                   domain=""
                   autofocus
                   required
                   placeholder="e.g. secrets.example.com"
                   class="dark:bg-gray-800 dark:text-white dark:border-gray-700" />

      <button type="submit"
              :disabled="isSubmitting"
              class="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-xl font-medium text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400 dark:focus:ring-offset-gray-900">
        {{ isSubmitting ? 'Adding...' : 'Continue' }}
      </button>
    </form>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import BasicFormAlerts from './BasicFormAlerts.vue';
import DomainInput from './DomainInput.vue';
import { useFormSubmission } from '@/utils/formSubmission';
import type { CustomDomainApiResponse } from '@/types/onetime';

const emit = defineEmits(['domain-added']);

const domain = ref('');
const shrimp = ref(window.shrimp);

const handleShrimp = (freshShrimp: string) => {
  shrimp.value = freshShrimp;
}

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: '/api/v1/account/domains/add',
  successMessage: 'Domain added successfully.',
  onSuccess: (data: CustomDomainApiResponse) => {
    console.log('Domain added:', data);
    domain.value = data.record.display_domain
    if (!domain.value) {
      console.error('Domain is undefined or empty');
    }
    try {
      emit('domain-added', domain.value);
    } catch (error) {
      console.error('Error emitting domain-added event:', error);
    }
  },
  onError: (data) => {
    console.error('Error adding domain:', data);
  },
  handleShrimp: handleShrimp,
});
</script>
