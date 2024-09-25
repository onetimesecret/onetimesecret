<script setup lang="ts">
import { ref, watch } from 'vue';
import APIKeyCard from '@/components/account/APIKeyCard.vue';
import { ApiTokenApiResponse } from '@/types/onetime';
import { useFormSubmission } from '@/utils/formSubmission';

interface Props {
  apitoken?: string;
  shrimp: string | undefined;
}

const props = defineProps<Props>();
const emit = defineEmits(['update:apitoken', 'update:shrimp']);

const localApiToken = ref(props.apitoken);
const localShrimp = ref(props.shrimp);

watch(() => props.apitoken, (newValue) => {
  localApiToken.value = newValue;
});

watch(() => props.shrimp, (newValue) => {
  localShrimp.value = newValue;
});

const handleShrimp = (freshShrimp: string) => {
  localShrimp.value = freshShrimp;
  emit('update:shrimp', freshShrimp);
}

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
  handleShrimp: handleShrimp,
});

</script>

<template>
  <form @submit.prevent="generateAPIKey">
    <input type="hidden"
           name="shrimp"
           :value="localShrimp" />

    <APIKeyCard :apitoken="localApiToken" />

    <div v-if="apiKeyError"
         class="mb-4 text-red-500">{{ apiKeyError }}</div>
    <div v-if="apiKeySuccess"
         class="mb-4 text-green-500">{{ apiKeySuccess }}</div>

    <button type="submit"
            class="hover:bg-gray-600 flex items-center justify-center w-full px-4 py-2 text-white bg-gray-500 rounded">
      <i class="fas fa-trash-alt mr-2"></i> {{ isGeneratingAPIKey ? 'Generating...' : 'Generate Token' }}
    </button>
    <p class="dark:text-gray-400 mt-2 text-sm text-gray-500"></p>
  </form>
</template>
