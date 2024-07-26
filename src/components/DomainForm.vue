<template>
  <div class="space-y-9 my-32">
    <form @submit.prevent="submitForm">
      <DomainInput v-model="domain"
                   :is-valid="true"
                   placeholder="e.g. secrets.example.com" />
      <button type="submit"
              :disabled="isSubmitting"
              class="hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-opacity-50 bg-brand-500 px-4 py-2 mt-4 text-lg text-white rounded">
        {{ isSubmitting ? 'Adding...' : 'Continue' }}
      </button>
    </form>
    <p v-if="error" class="text-red-500">{{ error }}</p>
    <p v-if="success" class="text-green-500">{{ success }}</p>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import DomainInput from './DomainInput.vue';
import { useFormSubmission } from '@/utils/formSubmission';

const domain = ref('');

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: '/api/v1/account/domain',
  successMessage: 'Domain added successfully.',
  getFormData: () => {
    const formData = new URLSearchParams();
    formData.append('domain', domain.value);
    return formData;
  },
  onSuccess: (data) => {
    // Handle successful domain addition
    console.log('Domain added:', data);
    // You might want to reset the form or perform other actions
    domain.value = '';
  },
  onError: (data) => {
    // Handle error in domain addition
    console.error('Error adding domain:', data);
  },
  handleShrimp: (newShrimp) => {
    // Update shrimp if needed
    console.log('New shrimp:', newShrimp);
    // You might want to update a shrimp ref or emit an event to update parent component
  }
});
</script>
