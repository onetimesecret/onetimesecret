<!-- src/views/incoming/IncomingSecretForm.vue -->

<script setup lang="ts">
  import { onMounted, ref } from 'vue';
  import { useIncomingSecret } from '@/composables/useIncomingSecret';
  import IncomingMemoInput from '@/components/incoming/IncomingMemoInput.vue';
  import IncomingRecipientDropdown from '@/components/incoming/IncomingRecipientDropdown.vue';
  import SecretContentInputArea from '@/components/secrets/form/SecretContentInputArea.vue';
  import LoadingOverlay from '@/components/common/LoadingOverlay.vue';
  import EmptyState from '@/components/EmptyState.vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const {
    form,
    errors,
    isSubmitting,
    memoMaxLength,
    isFeatureEnabled,
    recipients,
    isFormValid,
    validateMemo,
    validateSecret,
    validateRecipient,
    submit,
    loadConfig,
  } = useIncomingSecret();

  const isLoading = ref(true);
  const loadError = ref<string | null>(null);
  const secretContentRef = ref<InstanceType<typeof SecretContentInputArea> | null>(null);

  onMounted(async () => {
    try {
      await loadConfig();
    } catch (error) {
      loadError.value = error instanceof Error ? error.message : 'Failed to load configuration';
    } finally {
      isLoading.value = false;
    }
  });

  const handleTitleBlur = () => {
    validateMemo();
  };

  const handleRecipientBlur = () => {
    validateRecipient();
  };

  const handleSecretUpdate = (content: string) => {
    form.value.secret = content;
    if (errors.value.secret && content.trim()) {
      validateSecret();
    }
  };

  const handleSubmit = async () => {
    await submit();
  };

  const handleReset = () => {
    form.value.memo = '';
    form.value.secret = '';
    form.value.recipientId = '';
    errors.value = {};
    secretContentRef.value?.clearTextarea();
  };
</script>

<template>
  <div class="container mx-auto mt-16 max-w-3xl px-4 pb-20 sm:mt-20 sm:pb-24">
    <!-- Header -->
    <div class="mb-10">
      <h1 class="text-3xl font-bold text-gray-900 dark:text-white sm:text-4xl">
        {{ t('incoming.page_title') }}
      </h1>
      <p class="mt-3 text-base text-gray-600 dark:text-gray-400 sm:text-lg">
        {{ t('incoming.page_description') }}
      </p>
    </div>

    <!-- Loading State -->
    <LoadingOverlay
      :show="isLoading"
      :message="t('incoming.loading_config')" />

    <!-- Error State -->
    <EmptyState v-if="loadError">
      <template #title>
        {{ t('incoming.config_error_title') }}
      </template>
      <template #description>
        {{ loadError }}
      </template>
      <template #actionLabel>
        <!-- No action button for error state -->
      </template>
    </EmptyState>

    <!-- Feature Disabled -->
    <EmptyState v-else-if="!isFeatureEnabled">
      <template #title>
        {{ t('incoming.feature_disabled_title') }}
      </template>
      <template #description>
        {{ t('incoming.feature_disabled_description') }}
      </template>
      <template #actionLabel>
        <!-- No action button for disabled state -->
      </template>
    </EmptyState>

    <!-- Form -->
    <div
      v-else
      class="overflow-hidden rounded-2xl bg-white shadow-lg dark:bg-slate-800">
      <form
        @submit.prevent="handleSubmit"
        class="space-y-8 p-8 sm:p-10">
          <!-- Recipient Dropdown (First - like e-transfer) -->
          <IncomingRecipientDropdown
            v-model="form.recipientId"
            :recipients="recipients"
            :error="errors.recipientId"
            :disabled="isSubmitting"
            @blur="handleRecipientBlur" />

          <!-- Secret Content (Second) -->
          <div>
            <label
              for="secret-content"
              class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('incoming.secret_content_label') }}
              <span
                v-if="errors.secret"
                class="text-red-500">
                *
              </span>
            </label>

            <SecretContentInputArea
              ref="secretContentRef"
              :initial-content="form.secret"
              :disabled="isSubmitting"
              :max-length="10000"
              @update:content="handleSecretUpdate" />

            <span
              v-if="errors.secret"
              class="mt-1 block text-sm text-red-600 dark:text-red-400">
              {{ errors.secret }}
            </span>
          </div>

          <!-- Memo Input (Last - optional, like e-transfer) -->
          <IncomingMemoInput
            v-model="form.memo"
            :max-length="memoMaxLength"
            :error="errors.memo"
            :disabled="isSubmitting"
            @blur="handleTitleBlur" />

          <!-- Action Buttons -->
          <div class="flex flex-col gap-4 border-t border-gray-200 pt-8 dark:border-gray-700 sm:flex-row sm:items-center sm:justify-between">
            <button
              type="button"
              :disabled="isSubmitting"
              class="order-2 rounded-xl border-2 border-gray-300 bg-white px-6 py-3.5 text-base font-semibold text-gray-700 shadow-sm transition-all duration-200 hover:border-gray-400 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-slate-800 dark:text-gray-300 dark:hover:border-gray-500 dark:hover:bg-slate-700 sm:order-1"
              @click="handleReset">
              {{ t('incoming.reset_form') }}
            </button>

            <button
              type="submit"
              :disabled="isSubmitting || !isFormValid"
              class="order-1 flex items-center justify-center gap-2 rounded-xl px-8 py-3.5 text-base font-semibold text-white shadow-md transition-all duration-300 sm:order-2"
              :class="isFormValid && !isSubmitting
                ? 'bg-brand-500 hover:bg-brand-600 hover:shadow-xl text-white hover:scale-105 active:scale-100'
                : 'bg-gray-400 dark:bg-gray-600 cursor-not-allowed opacity-60'">
              <svg
                class="size-5 text-white"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                viewBox="0 0 24 24"
                aria-hidden="true">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
              </svg>
              {{ isSubmitting ? t('incoming.submitting') : t('incoming.submit_secret') }}
            </button>
          </div>
      </form>
    </div>
  </div>
</template>
