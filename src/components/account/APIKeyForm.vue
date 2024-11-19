<script setup lang="ts">
import APIKeyCard from '@/components/account/APIKeyCard.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { useCsrfStore } from '@/stores/csrfStore';
import { ApiTokenApiResponse, ApiRecordResponse } from '@/types/api';
import { ref, watch } from 'vue';

const csrfStore = useCsrfStore();

interface Props {
  apitoken?: string;
}

const props = defineProps<Props>();
const emit = defineEmits(['update:apitoken']);

const localApiToken = ref(props.apitoken);

watch(() => props.apitoken, (newValue) => {
  localApiToken.value = newValue;
});

const {
  isSubmitting: isGeneratingAPIKey,
  error: apiKeyError,
  success: apiKeySuccess,
  submitForm: generateAPIKey
} = useFormSubmission({
  url: '/api/v2/account/apitoken',
  successMessage: 'Token generated.',
  onSuccess: async (data: ApiTokenApiResponse) => {
    // @ts-expect-error "data.record" is defined only as BaseApiRecord
    const newToken = (data as ApiRecordResponse).record?.apitoken || '';
    localApiToken.value = newToken;
    emit('update:apitoken', newToken);
  },
});

</script>

<template>
  <form @submit.prevent="generateAPIKey">
    <input
      type="hidden"
      name="shrimp"
      :value="csrfStore.shrimp"
    />

    <APIKeyCard :apitoken="localApiToken" />

    <div
      v-if="apiKeyError"
      class="mb-4 text-red-500"
    >
      {{ apiKeyError }}
    </div>
    <div
      v-if="apiKeySuccess"
      class="mb-4 text-green-500"
    >
      {{ apiKeySuccess }}
    </div>

    <button
      type="submit"
      class="flex w-full items-center justify-center rounded bg-gray-500 px-4 py-2 text-white hover:bg-gray-600"
    >
      <i class="fas fa-trash-alt mr-2"></i> {{ isGeneratingAPIKey ? 'Generating...' : 'Generate Token' }}
    </button>
    <p class="mt-2 text-sm text-gray-500 dark:text-gray-400"></p>
  </form>
</template>
