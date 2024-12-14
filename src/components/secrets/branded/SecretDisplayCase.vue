<script setup lang="ts">
import BaseSecretDisplay from '@/components/secrets/branded/BaseSecretDisplay.vue';
import { useClipboard } from '@/composables/useClipboard';
import { useDomainBranding } from '@/composables/useDomainBranding';
import { Secret, SecretDetails } from '@/schemas/models';
import { ref , computed} from 'vue';

interface Props {
  record: Secret | null;
  details: SecretDetails | null;
  domainId: string;
  displayPoweredBy: boolean;
  submissionStatus?: {
    status: 'idle' | 'submitting' | 'success' | 'error';
    message?: string;
  };
}

const props = defineProps<Props>();

const alertClasses = computed(() => ({
  'mb-4 p-4 rounded-md': true,
  'bg-red-50 text-red-700 dark:bg-red-900 dark:text-red-100': props.submissionStatus?.status === 'error',
  'bg-green-50 text-green-700 dark:bg-green-900 dark:text-green-100': props.submissionStatus?.status === 'success'
}));

const domainBranding = useDomainBranding();

const hasImageError = ref(false);
const { isCopied, copyToClipboard } = useClipboard();

const copySecretContent = () => {
  if (props.record?.secret_value === undefined) {
    return;
  }

  copyToClipboard(props.record?.secret_value);
};

const handleImageError = () => {
  hasImageError.value = true;
};
// Prepare the standardized path to the logo image.
// Note that the file extension needs to be present but is otherwise not used.
const logoImage = ref<string>(`/imagine/${props.domainId}/logo.png`);
</script>

<template>
  <BaseSecretDisplay
    defaultTitle="You have a message"
    :instructions="domainBranding?.instructions_pre_reveal"
    :domainBranding="domainBranding">
    <!-- Alert display -->
    <div
      v-if="submissionStatus?.status === 'error' || submissionStatus?.status === 'success'"
      :class="alertClasses"
      role="alert">
      <div class="flex">
        <div class="shrink-0">
          <svg
            v-if="submissionStatus.status === 'error'"
            class="size-5"
            viewBox="0 0 20 20"
            fill="currentColor">
            <path
              fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
              clip-rule="evenodd"
            />
          </svg>
          <svg
            v-else
            class="size-5"
            viewBox="0 0 20 20"
            fill="currentColor">
            <path
              fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <div class="ml-3">
          <p class="text-sm">
            {{ submissionStatus.message || (submissionStatus.status === 'error' ? 'An error occurred' : 'Success') }}
          </p>
        </div>
      </div>
    </div>

    <template #logo>
      <!-- Brand Icon -->
      <div class="relative mx-auto sm:mx-0">
        <div
          :class="{
            'rounded-lg': domainBranding?.corner_style === 'rounded',
            'rounded-full': domainBranding?.corner_style === 'pill',
            'rounded-none': domainBranding?.corner_style === 'square'
          }"
          class="flex size-14 items-center justify-center bg-gray-100 dark:bg-gray-700 sm:size-16">
          <!-- Default lock icon -->
          <svg
            v-if="!logoImage || hasImageError"
            class="size-8 text-gray-400 dark:text-gray-500"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
            />
          </svg>

          <!-- Logo -->
          <img
            v-if="logoImage && !hasImageError"
            :src="logoImage"
            alt="Brand logo"
            class="size-16 object-contain"
            :class="{
              'rounded-lg': domainBranding?.corner_style === 'rounded',
              'rounded-full': domainBranding?.corner_style === 'pill',
              'rounded-none': domainBranding?.corner_style === 'square'
            }"
            @error="handleImageError"
          />
        </div>
      </div>
    </template>

    <template #content>
      <textarea
        class="min-h-32 w-full resize-none rounded-md border border-gray-300 bg-gray-100
            font-mono text-base focus:outline-none
              focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white  sm:min-h-36"
        readonly
        :rows="details?.display_lines"
        :value="record?.secret_value"></textarea>
    </template>

    <template #action-button>
      <button
        @click="copySecretContent"
        :title="isCopied ? 'Copied!' : 'Copy to clipboard'"
        class="rounded-md bg-gray-200 p-1.5
          transition-colors duration-200 hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-brand-500
          dark:bg-gray-600 dark:hover:bg-gray-500"
        aria-label="Copy to clipboard">
        <svg
          v-if="!isCopied"
          xmlns="http://www.w3.org/2000/svg"
          class="size-5 text-gray-600 dark:text-gray-300"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
          />
        </svg>
        <svg
          v-else
          xmlns="http://www.w3.org/2000/svg"
          class="size-5 text-green-500"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M5 13l4 4L19 7"
          />
        </svg>
      </button>
    </template>
  </BaseSecretDisplay>
</template>

<style></style>
