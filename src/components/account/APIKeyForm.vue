<!-- src/components/account/APIKeyForm.vue -->

<script setup lang="ts">
  import APIKeyCard from '@/components/account/APIKeyCard.vue';
  import { useFormSubmission } from '@/composables/useFormSubmission';
  import { responseSchemas } from '@/schemas/api/responses';
  import { useCsrfStore } from '@/stores/csrfStore';
  import { ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  const csrfStore = useCsrfStore();
  const { t } = useI18n();

  interface Props {
    apitoken?: string;
  }

  const props = defineProps<Props>();
  const emit = defineEmits(['update:apitoken']);

  const localApiToken = ref(props.apitoken);

  watch(
    () => props.apitoken,
    (newValue) => {
      localApiToken.value = newValue;
    }
  );

  const {
    isSubmitting: isGeneratingAPIKey,
    error: apiKeyError,
    success: apiKeySuccess,
    submitForm: generateAPIKey,
  } = useFormSubmission({
    url: '/api/v2/account/apitoken',
    successMessage: t('token-generated'),
    schema: responseSchemas.apiToken,
    onSuccess: async (data) => {
      // data is now properly typed as ApiTokenResponse
      const newToken = data.record?.apitoken || '';
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
      class="mb-4 text-red-500">
      {{ apiKeyError }}
    </div>
    <div
      v-if="apiKeySuccess"
      class="mb-4 text-green-500">
      {{ apiKeySuccess }}
    </div>

    <button
      type="submit"
      class="flex w-full items-center justify-center rounded bg-gray-500 px-4 py-2
        text-white hover:bg-gray-600">
      <svg
        class="mr-2 size-4"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="currentColor">
        <path
          fill-rule="evenodd"
          d="M15.75 1.5a6.75 6.75 0 00-6.651 7.906c.067.39-.032.717-.221.906l-6.5 6.499a3 3 0 00-.878 2.121v2.818c0 .414.336.75.75.75H6a.75.75 0 00.75-.75v-1.5h1.5A.75.75 0 009 19.5V18h1.5a.75.75 0 00.53-.22l2.658-2.658c.19-.189.517-.288.906-.22A6.75 6.75 0 1015.75 1.5zm0 3a.75.75 0 000 1.5A2.25 2.25 0 0118 8.25a.75.75 0 001.5 0 3.75 3.75 0 00-3.75-3.75z"
          clip-rule="evenodd"
        />
      </svg>
      {{ isGeneratingAPIKey ? 'Generating...' : 'Generate Token' }}
    </button>
    <p class="mt-2 text-sm text-gray-500 dark:text-gray-400"></p>
  </form>
</template>
