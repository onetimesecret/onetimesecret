<template>
  <div class="w-full bg-white dark:bg-gray-800 rounded-lg p-4 sm:p-6">
    <!-- Header Section -->
    <div class="flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4 mb-6">
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

      <!-- Title and Instructions -->
      <div class="flex-1 text-center sm:text-left">
        <div class="min-h-[4rem] sm:h-[4.5rem]">
          <h2 class="text-gray-900 dark:text-gray-200 text-base sm:text-lg font-medium mb-1 sm:mb-2 leading-normal"
              :style="{ fontFamily: domainBranding?.font_family }">
            {{ record?.has_passphrase ? $t('web.shared.requires_passphrase') : 'You have a message' }}
          </h2>
          <p class="text-gray-600 dark:text-gray-400 text-xs sm:text-sm leading-normal"
             :style="{ fontFamily: domainBranding?.font_family }">
            {{ domainBranding?.instructions_pre_reveal || $t('web.shared.pre_reveal_default') }}
          </p>
        </div>
      </div>
    </div>

    <!-- Alert Messages -->
    <BasicFormAlerts :success="success"
                     :error="error"
                     role="alert"
                     class="mb-4" />

    <!-- Content Area -->
    <div class="mt-3 sm:mt-4 mb-3 sm:mb-4">
      <div class="w-full min-h-28 bg-gray-100 dark:bg-gray-700 flex items-center justify-center p-4"
           :class="{
            'rounded-lg': domainBranding?.corner_style === 'rounded',
            'rounded-xl': domainBranding?.corner_style === 'pill',
            'rounded-none': domainBranding?.corner_style === 'square'
          }">
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
      </div>
    </div>

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

    <!-- Footer -->
    <div class="flex justify-between items-baseline p-3 sm:p-4 mt-4">
      <p class="text-xs sm:text-sm text-gray-500 dark:text-gray-400 italic flex items-center">
        <svg class="w-4 h-4 mr-1"
             viewBox="0 0 24 24"
             fill="none"
             stroke="currentColor">
          <path stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        {{ $t('web.COMMON.careful_only_see_once') }}
      </p>
    </div>
  </div>
</template>

<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import { useFormSubmission } from '@/composables/useFormSubmission';
import { useCsrfStore } from '@/stores/csrfStore';
import type { SecretData, SecretDetails, BrandSettings } from '@/types/onetime';
import { ref } from 'vue';

interface Props {
  secretKey: string;
  record: SecretData | null;
  details: SecretDetails | null;
  domainBranding?: BrandSettings;
  domainId: string;
}

const props = defineProps<Props>();

const emit = defineEmits<{
  (e: 'secret-loaded', data: { record: SecretData; details: SecretDetails; }): void;
}>();

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
