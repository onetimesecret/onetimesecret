<template>
  <div class="space-y-9 my-16">

    <BasicFormAlerts :success="success" :error="error" />

    <form @submit.prevent="submitForm">
      <input type="hidden"
             name="shrimp"
             :value="shrimp" />

      <DomainInput v-model="domain"
                   :is-valid="true"
                   domain=""
                   placeholder="e.g. secrets.example.com" />

      <button type="submit"
              :disabled="isSubmitting"
              class="hover:bg-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-opacity-50 bg-brand-500 px-4 py-2 mt-4 text-lg text-white rounded">
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
  onSuccess: (data: Record<string, string>) => {
    // Handle successful domain addition
    console.log('Domain added:', data);
    // You might want to reset the form or perform other actions
    domain.value = '';
  },
  onError: (data: Record<string, string>) => {
    // Handle error in domain addition
    console.error('Error adding domain:', data);
  },
  handleShrimp: handleShrimp,
});
</script>
