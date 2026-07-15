<!-- src/apps/secret/components/branded/SecretConfirmationForm.vue -->

<script setup lang="ts">
  import { brandSettingsSchema } from '@/schemas/shapes/v3/custom-domain';
  import type { Secret, SecretDetails } from '@/schemas/shapes/v3/secret';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { ref, computed } from 'vue';
  import { useI18n } from 'vue-i18n';

  import BaseSecretDisplay from './BaseSecretDisplay.vue';

  // Default brand settings for when no custom branding is configured
  const defaultBrandSettings = brandSettingsSchema.parse({});

  interface Props {
    secretIdentifier: string;
    record: Secret | null;
    details: SecretDetails | null;
    domainId: string;
    isSubmitting: boolean;
    error: unknown;
  }

  const props = defineProps<Props>();

  const i18n = useI18n();
  const { t } = i18n;

  const emit = defineEmits(['user-confirmed']);
  // const useSecret = useSecret();
  const passphrase = ref('');

  const submitForm = async () => {
    emit('user-confirmed', passphrase.value);
  };

  const productIdentity = useProductIdentity();

  // Use computed refs from identityStore directly - already parsed with v3 schema
  const cornerClass = computed(() => productIdentity.cornerClass);
  const fontFamilyClass = computed(() => productIdentity.fontFamilyClass);
  const headingFontClass = computed(() => productIdentity.headingFontClass);

  const buttonText = computed(() => props.isSubmitting ? t('web.COMMON.submitting') : t('web.COMMON.click_to_continue'));
</script>

<template>
  <BaseSecretDisplay
    :default-title="t('web.secrets.you_have_a_message')"
    :preview-i18n="i18n"
    :domain-branding="productIdentity.brand ?? defaultBrandSettings"
    :corner-class="cornerClass"
    :font-class="fontFamilyClass"
    :heading-class="headingFontClass">
    <template #content>
      <div
        class="flex items-center text-gray-400 dark:text-gray-500"
        role="status"
        :aria-label="t('web.secrets.content_status')">
        <svg
          class="mr-2 size-5"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          aria-hidden="true">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M13.875 18.825A10.05 10.05 0 0112 19c-4.478 0-8.268-2.943-9.543-7A9.97 9.97 0 014.02 8.971m5.858.908a3 3 0 114.243 4.243M9.878 9.878l4.242 4.242M9.88 9.88l-3.29-3.29m7.532 7.532l3.29 3.29M3 3l3.59 3.59m0 0A9.953 9.953 0 0112 5c4.478 0 8.268 2.943 9.543 7a10.025 10.025 0 01-4.132 5.411m0 0L21 21" />
        </svg>
        <span class="text-sm">{{ t('web.secrets.content_hidden') }}</span>
      </div>
    </template>

    <template #action-button>
      <form
        @submit.prevent="submitForm"
        :aria-label="t('web.secrets.secret_access_form')">
        <!-- Error Message -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-if="error"
          class="mb-4 rounded-md bg-red-50 p-4 text-sm
            text-red-700 dark:bg-red-900/50 dark:text-red-200"
          role="alert">
          {{ error }}
        </div>

        <!-- Passphrase Input -->
        <div
          v-if="record?.has_passphrase"
          class="mb-4 space-y-2">
          <label
            :for="'passphrase-' + secretIdentifier"
            class="sr-only">
            {{ t('web.COMMON.enter_passphrase_here') }}
          </label>
          <input
            v-model="passphrase"
            :id="'passphrase-' + secretIdentifier"
            type="password"
            name="passphrase"
            :class="[
              cornerClass,
              'w-full border border-gray-300 px-4 py-2 focus:ring-2 focus:ring-offset-2 focus:outline-none dark:border-gray-600 dark:bg-gray-700 dark:text-white',
            ]"
            autocomplete="current-password"
            :aria-label="t('web.COMMON.enter_passphrase_here')"
            :placeholder="t('web.COMMON.enter_passphrase_here')"
            aria-required="true" />
        </div>

        <!-- Submit Button -->
        <button
          type="submit"
          :disabled="isSubmitting"
          :class="[
            cornerClass,
            fontFamilyClass,
            productIdentity.buttonTextLight ? 'text-white' : 'text-gray-900',
            'w-full bg-brand-500 py-3 text-base font-medium transition-colors hover:bg-brand-600 disabled:cursor-not-allowed disabled:opacity-50 sm:text-lg',
          ]"
          class="focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 focus:outline-none"
          data-testid="secret-reveal-submit"
          aria-live="polite">
          <span class="sr-only">{{ buttonText }}</span>
          {{ isSubmitting ? t('web.COMMON.submitting') : t('web.COMMON.click_to_continue') }}
        </button>
      </form>
    </template>
  </BaseSecretDisplay>
</template>

<style>
  .line-clamp-6 {
    display: -webkit-box;
    -webkit-line-clamp: 3;
    -webkit-box-orient: vertical;
    overflow: hidden;
    line-clamp: 3;
  }

  /* Ensure focus outline is visible in all color schemes */
  :focus {
    outline: 2px solid currentColor;
    outline-offset: 2px;
  }
</style>
