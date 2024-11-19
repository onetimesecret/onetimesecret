<template>
  <BaseSecretDisplay defaultTitle="You have a message"
                     :domainBranding="domainBranding"
                     :instructions="domainBranding?.instructions_pre_reveal">
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
      <div class="text-gray-400 dark:text-gray-500 flex items-center">
        <svg class="w-5 h-5 mr-2"
             viewBox="0 0 24 24"
             fill="none"
             stroke="currentColor">
          <path stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7A9.97 9.97 0 014.02 8.971m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
        </svg>
        <span class="text-sm">Content hidden</span>
      </div>
    </template>

    <template #action-button>

      <!-- Form -->
      <form @submit.prevent="submitForm"
            class="space-y-4"
            aria-label="Secret confirmation form">
        <input name="shrimp"
               type="hidden"
               :value="csrfStore.shrimp" />
        <input name="continue"
               type="hidden"
               value="true" />

        <!-- Passphrase Input -->
        <div v-if="record?.has_passphrase"
             class="space-y-2">
          <input v-model="passphrase"
                 type="password"
                 name="passphrase"
                 :class="{
                  'rounded-lg': domainBranding?.corner_style === 'rounded',
                  'rounded-2xl': domainBranding?.corner_style === 'pill',
                  'rounded-none': domainBranding?.corner_style === 'square',
                       'w-full px-4 py-2 border border-gray-300 dark:border-gray-600 focus:ring-2 focus:ring-offset-2 focus:outline-none dark:bg-gray-700 dark:text-white': true
                     }"
                 :style="{ fontFamily: domainBranding?.font_family }"
                 autocomplete="current-password"
                 :aria-label="$t('web.COMMON.enter_passphrase_here')"
                 :placeholder="$t('web.COMMON.enter_passphrase_here')" />
        </div>

        <!-- Submit Button -->
        <button type="submit"
                :disabled="isSubmitting"
                :class="{
                  'rounded-lg': domainBranding?.corner_style === 'rounded',
                  'rounded-full': domainBranding?.corner_style === 'pill',
                  'rounded-none': domainBranding?.corner_style === 'square',
                  'w-full py-3 text-base sm:text-lg font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed': true
                }"
                :style="{
                  backgroundColor: domainBranding?.primary_color,
                       color: domainBranding?.button_text_light ? '#ffffff' : '#000000',
                       fontFamily: domainBranding?.font_family
                     }"
                aria-live="polite">
          {{ isSubmitting ? $t('web.COMMON.submitting') : $t('web.COMMON.click_to_continue') }}
        </button>
      </form>

      <!-- Alert Messages -->
      <BasicFormAlerts :success="success"
                       :error="error"
                       role="alert"
                       class="mt-8 mb-4" />
    </template>
  </BaseSecretDisplay>
</template>

<style>
.line-clamp-6 {
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

/*p {
  transition: all 0.3s ease-in-out;
}*/
</style>

<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import { useDomainBranding } from '@/composables/useDomainBranding';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { SecretData, SecretDetails } from '@/schemas/models';
import { useCsrfStore } from '@/stores/csrfStore';
import { ref } from 'vue';

import BaseSecretDisplay from './BaseSecretDisplay.vue';



interface Props {
  secretKey: string;
  record: SecretData | null;
  details: SecretDetails | null;
  domainId: string;
}

const props = defineProps<Props>();

const emit = defineEmits<{
  (e: 'secret-loaded', data: { record: SecretData; details: SecretDetails; }): void;
}>();

const domainBranding = useDomainBranding();

const csrfStore = useCsrfStore();
const passphrase = ref('');

const {
  isSubmitting,
  error,
  success,
  submitForm
} = useFormSubmission({
  url: `/api/v2/secret/${props.secretKey}`,
  successMessage: '',
  onSuccess: (data: { record: SecretData; details: SecretDetails; }) => {
    emit('secret-loaded', {
      record: data.record,
      details: data.details
    });
  }
});

const hasImageError = ref(false);

const handleImageError = () => {
  hasImageError.value = true;
};
// Prepare the standardized path to the logo image.
// Note that the file extension needs to be present but is otherwise not used.
const logoImage = ref<string>(`/imagine/${props.domainId}/logo.png`);
</script>
