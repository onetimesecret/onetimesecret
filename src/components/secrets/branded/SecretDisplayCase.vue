<template>
  <BaseSecretDisplay defaultTitle="You have a message"
                     :domainBranding="domainBranding"
                     :instructions="domainBranding.instructions_pre_reveal">
    <template #logo>
      <!-- Brand Icon -->
      <div class="relative mx-auto sm:mx-0">
        <div :class="{
          'rounded-lg': domainBranding?.corner_style === 'rounded',
          'rounded-full': domainBranding?.corner_style === 'pill',
          'rounded-none': domainBranding?.corner_style === 'square'
        }"
             class="w-14 h-14 sm:w-16 sm:h-16 bg-gray-100 dark:bg-gray-700 flex items-center justify-center">
          <!-- Default lock icon -->
          <svg v-if="!logoImage || hasImageError"
               class="w-8 h-8 text-gray-400 dark:text-gray-500"
               viewBox="0 0 24 24"
               fill="none"
               stroke="currentColor">
            <path stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
          </svg>

          <!-- Logo -->
          <img v-if="logoImage && !hasImageError"
               :src="logoImage"
               alt="Brand logo"
               class="h-16 w-16 object-contain"
               :class="{
                'rounded-lg': domainBranding?.corner_style === 'rounded',
                'rounded-full': domainBranding?.corner_style === 'pill',
                'rounded-none': domainBranding?.corner_style === 'square'
              }"
               @error="handleImageError" />
        </div>
      </div>
    </template>

    <template #content>
      <textarea class="w-full min-h-32 sm:min-h-36 border border-gray-300 rounded-md resize-none
            dark:border-gray-600 dark:text-white dark:bg-gray-800
              focus:outline-none focus:ring-2 focus:ring-brand-500  font-mono text-base  bg-gray-100"
                readonly
                :rows="details?.display_lines"
                :value="record?.secret_value"></textarea>
    </template>

    <template #action-button>
      <button @click="copySecretContent"
              :title="isCopied ? 'Copied!' : 'Copy to clipboard'"
              class="p-1.5 bg-gray-200 dark:bg-gray-600 rounded-md hover:bg-gray-300 dark:hover:bg-gray-500 focus:outline-none focus:ring-2 focus:ring-brand-500 transition-colors duration-200"
              aria-label="Copy to clipboard">
        <svg v-if="!isCopied"
             xmlns="http://www.w3.org/2000/svg"
             class="h-5 w-5 text-gray-600 dark:text-gray-300"
             fill="none"
             viewBox="0 0 24 24"
             stroke="currentColor">
          <path stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
        <svg v-else
             xmlns="http://www.w3.org/2000/svg"
             class="h-5 w-5 text-green-500"
             fill="none"
             viewBox="0 0 24 24"
             stroke="currentColor">
          <path stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7" />
        </svg>
      </button>
    </template>
  </BaseSecretDisplay>
</template>

<style></style>

<script setup lang="ts">
import { useClipboard } from '@/composables/useClipboard';
import { BrandSettings, SecretData, SecretDetails } from '@/types/onetime';
import { ref } from 'vue';
import BaseSecretDisplay from './BaseSecretDisplay.vue';


interface Props {
  secretKey: string;
  record: SecretData | null;
  details: SecretDetails | null;
  domainBranding: BrandSettings;
  domainId: string;
}

const props = defineProps<Props>();

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
