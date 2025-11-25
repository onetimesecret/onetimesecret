<script setup lang="ts">
import { IncomingMemoInput, IncomingRecipientDropdown } from '@/components/incoming';
import { useIncomingSecret } from '@/composables/useIncomingSecret';
import { useCsrfStore } from '@/stores/csrfStore';
import { useRouter } from 'vue-router';

const { t } = useI18n();
const router = useRouter();
const csrfStore = useCsrfStore();

const {
  form,
  errors,
  isLoading,
  isSubmitting,
  configError,
  isEnabled,
  recipients,
  memoMaxLength,
  submit,
  reset,
} = useIncomingSecret({
  autoLoadConfig: true,
  onSuccess: (response) => {
    // Navigate to success view with the metadata key
    const metadataKey = response.record?.metadata?.key;
    if (metadataKey) {
      router.push({
        name: 'IncomingSuccess',
        params: { key: metadataKey },
      });
    }
  },
});

const handleSubmit = async (event?: Event) => {
  event?.preventDefault();
  await submit();
};
</script>

<template>
  <div class="mx-auto max-w-2xl px-4 py-8 sm:px-6 lg:px-8">
    <!-- Loading State -->
    <div
      v-if="isLoading"
      class="flex min-h-[200px] items-center justify-center">
      <div class="text-center">
        <svg
          class="mx-auto size-8 animate-spin text-brand-500"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24">
          <circle
            class="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            stroke-width="4"/>
          <path
            class="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"/>
        </svg>
        <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
          {{ t('incoming.loading_config') }}
        </p>
      </div>
    </div>

    <!-- Config Error State -->
    <div
      v-else-if="configError"
      class="rounded-lg bg-red-50 p-6 text-center dark:bg-red-900/20">
      <h2 class="text-lg font-medium text-red-800 dark:text-red-200">
        {{ t('incoming.config_error_title') }}
      </h2>
      <p class="mt-2 text-sm text-red-600 dark:text-red-400">
        {{ configError }}
      </p>
    </div>

    <!-- Feature Disabled State -->
    <div
      v-else-if="!isEnabled"
      class="rounded-lg bg-yellow-50 p-6 text-center dark:bg-yellow-900/20">
      <h2 class="text-lg font-medium text-yellow-800 dark:text-yellow-200">
        {{ t('incoming.feature_disabled_title') }}
      </h2>
      <p class="mt-2 text-sm text-yellow-600 dark:text-yellow-400">
        {{ t('incoming.feature_disabled_description') }}
      </p>
    </div>

    <!-- Form -->
    <div
      v-else
      class="space-y-6">
      <!-- Header -->
      <div class="text-center">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-gray-100">
          {{ t('incoming.page_title') }}
        </h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ t('incoming.page_description') }}
        </p>
      </div>

      <!-- Taglines -->
      <div class="text-center text-sm text-gray-500 dark:text-gray-400">
        <p>{{ t('incoming.tagline1') }}</p>
        <p>{{ t('incoming.tagline2') }}</p>
      </div>

      <!-- Form Card -->
      <div class="overflow-hidden rounded-lg bg-white shadow-md dark:bg-gray-800">
        <form
          class="space-y-6 p-6"
          @submit.prevent="handleSubmit">
          <!-- CSRF Token -->
          <input
            type="hidden"
            name="shrimp"
            :value="csrfStore.shrimp" />

          <!-- Recipient Dropdown -->
          <IncomingRecipientDropdown
            v-model="form.recipientHash"
            :recipients="recipients"
            :error="errors.recipient"
            :disabled="isSubmitting" />

          <!-- Memo Input -->
          <IncomingMemoInput
            v-model="form.memo"
            :max-length="memoMaxLength"
            :error="errors.memo"
            :disabled="isSubmitting" />

          <!-- Secret Content -->
          <div class="space-y-1">
            <label
              for="incoming-secret"
              class="block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('incoming.secret_content_label') }}
            </label>
            <textarea
              id="incoming-secret"
              v-model="form.secret"
              rows="5"
              :disabled="isSubmitting"
              :class="[
                'w-full resize-y rounded-md border px-4 py-2',
                'focus:outline-none focus:ring-2',
                errors.secret
                  ? 'border-red-300 focus:border-red-500 focus:ring-red-500 dark:border-red-600'
                  : 'border-gray-300 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600',
                'dark:bg-gray-700 dark:text-gray-200',
                isSubmitting ? 'cursor-not-allowed opacity-50' : '',
              ]"
              :placeholder="t('incoming.secret_content_placeholder')"
              :aria-describedby="
                errors.secret ? 'secret-error' : 'secret-hint'
              "></textarea>
            <p
              v-if="errors.secret"
              id="secret-error"
              class="text-xs text-red-600 dark:text-red-400">
              {{ errors.secret }}
            </p>
            <p
              v-else
              id="secret-hint"
              class="text-xs text-gray-500 dark:text-gray-400">
              {{ t('incoming.secret_content_hint') }}
            </p>
          </div>

          <!-- Actions -->
          <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
            <button
              type="button"
              :disabled="isSubmitting"
              class="rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
              @click="reset">
              {{ t('incoming.reset_form') }}
            </button>
            <button
              type="submit"
              :disabled="isSubmitting"
              class="rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
              {{
                isSubmitting ? t('incoming.submitting') : t('incoming.submit_secret')
              }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
