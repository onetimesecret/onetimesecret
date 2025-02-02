<script setup lang="ts">
import DomainInput from '@/components/DomainInput.vue'
import ErrorDisplay from '@/components/ErrorDisplay.vue'
import { createDomainRequestSchema } from '@/schemas/api/requests';
import { ref, computed } from 'vue';
import { createError, type ApplicationError } from '@/schemas/errors';
import { useI18n } from 'vue-i18n';

defineProps<{
  isSubmitting?: boolean,
}>();

const domain = ref('');
// Initialize as null to avoid showing initial error state
const isValid = ref<boolean|null>(null);
const localError = ref<ApplicationError|null>();
const { t } = useI18n();

const emit = defineEmits<{
  (e: 'submit', domain: string): void
  (e: 'back'): void
}>();

const placeholderText = computed(() => `${t('e-g-example')} ${t('secrets-example-dot-com')}`);

const handleSubmit = () => {
  localError.value = null;

  // Check for empty submission first
  if (!domain.value.trim()) {
    localError.value = createError(t('please-enter-a-domain-name', ''), "human");
    isValid.value = false;
    return;
  }

  try {
    const validated = createDomainRequestSchema.parse({ domain: domain.value });
    isValid.value = true;
    emit('submit', validated.domain);
  } catch {
    isValid.value = false;
    localError.value = createError(t('please-enter-a-domain-name', 'valid'), "human");
  }
};
</script>

<template>
  <div class="mx-auto my-16 max-w-full space-y-9 px-4 dark:bg-gray-900 sm:px-6 lg:px-8">
    <form @submit.prevent="handleSubmit" class="space-y-6">
      <DomainInput
        v-model="domain"
        :is-valid="isValid"
        autofocus
        required
        :placeholder="placeholderText"
        class="dark:border-gray-700 dark:bg-gray-800 dark:text-white"
      />

      <!-- Add error display -->
      <ErrorDisplay
        v-if="localError"
        :error="localError"
      />

      <div
        class="flex flex-col-reverse
        space-y-4 space-y-reverse sm:flex-row sm:space-x-4 sm:space-y-0">
        <!-- Cancel/Back Button -->
        <button
          type="button"
          @click="$emit('back')"
          class="inline-flex w-full items-center justify-center rounded-md
            border border-gray-300
            bg-white px-4 py-2 text-base
            font-medium text-gray-700 shadow-sm
            hover:bg-gray-50
            focus:outline-none
            focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 dark:border-gray-600
            dark:bg-gray-800 dark:text-gray-200 dark:hover:bg-gray-700
            dark:focus:ring-offset-gray-900 sm:w-1/2"
          aria-label="`t('go-back-to-previous-page')`">
          <svg
            class="-ml-1 mr-2 size-5"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            />
          </svg>
          {{ $t('back') }}
        </button>

        <!-- Submit Button -->
        <button
          type="submit"
          :disabled="isSubmitting"
          class="inline-flex w-full items-center justify-center rounded-md
            border border-transparent
            bg-brand-600 px-4 py-2 text-base
            font-medium text-white shadow-sm
            hover:bg-brand-700
            focus:outline-none
            focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed
            disabled:opacity-50 dark:bg-brand-500
            dark:hover:bg-brand-400 dark:focus:ring-offset-gray-900
            sm:w-1/2"
          aria-live="polite">
          <span
            v-if="isSubmitting"
            class="inline-flex items-center">
            <svg
              class="-ml-1 mr-2 size-5 animate-spin text-white"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24">
              <circle
                class="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                stroke-width="4"
              />
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              />
            </svg>
            {{ $t('adding_ellipses') }}...
          </span>
          <span v-else>{{ $t('continue') }}</span>
        </button>
      </div>
    </form>
  </div>
</template>
