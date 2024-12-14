<script setup lang="ts">
import { useClipboard } from '@/composables/useClipboard';
import { Secret, SecretDetails } from '@/schemas/models';
import { computed } from 'vue';

import BaseSecretDisplay from './BaseSecretDisplay.vue';

interface Props {
  record: Secret | null;
  details: SecretDetails | null;
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


const { isCopied, copyToClipboard } = useClipboard();

const copySecretContent = () => {
  if (props.record?.secret_value === undefined) {
    return;
  }

  copyToClipboard(props.record?.secret_value);
};

const closeTruncatedWarning = (event: Event) => {
  (event.target as HTMLElement).closest('.bg-brandcomp-100')?.remove();
};
</script>

<template>
  <BaseSecretDisplay
    :displayPoweredBy="displayPoweredBy">
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
    <template #content>
      <div class="relative">
        <textarea
          v-if="record?.secret_value"
          class="w-full resize-none rounded-md border border-gray-300 bg-gray-100 px-3
            py-2 font-mono text-base
            leading-[1.2] tracking-wider focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white"
          readonly
          :rows="details?.display_lines"
          :value="record?.secret_value"></textarea>
        <div
          v-else
          class="text-red-500 dark:text-red-400">
          Secret value not available
        </div>
        <button
          @click="copySecretContent"
          :title="isCopied ? 'Copied!' : 'Copy to clipboard'"
          class="absolute right-2 top-2 rounded-md bg-gray-200 p-1.5
            transition-colors duration-200 hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-600 dark:hover:bg-gray-500"
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
      </div>
    </template>

    <template #warnings>
      <div>
        <p
          v-if="!record?.verification"
          class="text-sm text-gray-500 dark:text-gray-400">
          ({{ $t('web.COMMON.careful_only_see_once') }})
        </p>

        <div
          v-if="record?.is_truncated"
          class="border-l-4 border-brandcomp-500 bg-brandcomp-100 p-4
            text-sm text-blue-700 dark:bg-blue-800 dark:text-blue-200">
          <button
            type="button"
            class="float-right"
            @click="closeTruncatedWarning">
            &times;
          </button>
          <strong>{{ $t('web.COMMON.warning') }}</strong>
          {{ $t('web.shared.secret_was_truncated') }} {{ record.original_size }}.
        </div>
      </div>
    </template>

    <template #cta>
      <div class="mt-4">
        <div
          v-if="!record?.verification"
          class="my-16 mb-4 border-l-4 border-gray-400 bg-gray-100 p-4
            text-gray-700 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-300">
          <button
            type="button"
            class="float-right hover:text-gray-900 dark:hover:text-gray-100"
            onclick="this.parentElement.remove()">
            &times;
          </button>
          <p>
            Once you've finished viewing the secret, feel free to navigate away from this page or
            close the window.
          </p>
        </div>
        <div v-else>
          <a
            href="/signin"
            class="block w-full rounded-md border border-brand-500 bg-white px-4 py-2
              text-center text-brand-500 hover:bg-brand-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-brand-400 dark:bg-gray-800 dark:text-brand-400 dark:hover:bg-gray-700">
            {{ $t('web.COMMON.login_to_your_account') }}
          </a>
        </div>
      </div>
    </template>
  </BaseSecretDisplay>
</template>
