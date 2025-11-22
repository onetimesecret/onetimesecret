<!-- src/views/incoming/IncomingSecretForm.vue -->

<script setup lang="ts">
  import { onMounted, ref } from 'vue';
  import { useIncomingSecret } from '@/composables/useIncomingSecret';
  import IncomingMemoInput from '@/components/incoming/IncomingMemoInput.vue';
  import IncomingRecipientDropdown from '@/components/incoming/IncomingRecipientDropdown.vue';
  import SecretContentInputArea from '@/components/secrets/form/SecretContentInputArea.vue';
  import LoadingOverlay from '@/components/common/LoadingOverlay.vue';
  import EmptyState from '@/components/EmptyState.vue';

  const {
    form,
    errors,
    isSubmitting,
    memoMaxLength,
    isFeatureEnabled,
    recipients,
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
  <div class="container mx-auto mt-24 max-w-3xl px-4">
    <!-- Header -->
    <div class="mb-8">
      <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
        {{ $t('web.incoming.page_title') }}
      </h1>
      <p class="mt-2 text-gray-600 dark:text-gray-400">
        {{ $t('web.incoming.page_description') }}
      </p>
    </div>

    <!-- Loading State -->
    <LoadingOverlay
      :show="isLoading"
      :message="$t('web.incoming.loading_config')" />

    <!-- Error State -->
    <EmptyState v-if="loadError">
      <template #title>
        {{ $t('web.incoming.config_error_title') }}
      </template>
      <template #description>
        {{ loadError }}
      </template>
    </EmptyState>

    <!-- Feature Disabled -->
    <EmptyState v-else-if="!isFeatureEnabled">
      <template #title>
        {{ $t('web.incoming.feature_disabled_title') }}
      </template>
      <template #description>
        {{ $t('web.incoming.feature_disabled_description') }}
      </template>
    </EmptyState>

    <!-- Form -->
    <div
      v-else
      class="rounded-lg bg-white p-6 shadow-sm dark:bg-slate-800 sm:p-8">
      <form
        @submit.prevent="handleSubmit"
        class="space-y-6">
          <!-- Title Input -->
          <IncomingMemoInput
            v-model="form.memo"
            :max-length="memoMaxLength"
            :error="errors.memo"
            :disabled="isSubmitting"
            @blur="handleTitleBlur" />

          <!-- Recipient Dropdown -->
          <IncomingRecipientDropdown
            v-model="form.recipientId"
            :recipients="recipients"
            :error="errors.recipientId"
            :disabled="isSubmitting"
            @blur="handleRecipientBlur" />

          <!-- Secret Content -->
          <div>
            <label
              for="secret-content"
              class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ $t('web.incoming.secret_content_label') }}
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

          <!-- Action Buttons -->
          <div class="flex items-center justify-between gap-4 border-t border-gray-200 pt-6 dark:border-gray-700">
            <button
              type="button"
              :disabled="isSubmitting"
              class="rounded-lg border border-gray-300 px-6 py-3 text-base font-medium text-gray-700 transition-colors duration-200 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-slate-700"
              @click="handleReset">
              {{ $t('web.incoming.reset_form') }}
            </button>

            <button
              type="submit"
              :disabled="isSubmitting"
              class="rounded-lg bg-blue-600 px-6 py-3 text-base font-medium text-white transition-colors duration-200 hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-blue-500 dark:hover:bg-blue-600">
              {{ isSubmitting ? $t('web.incoming.submitting') : $t('web.incoming.submit_secret') }}
            </button>
          </div>
      </form>
    </div>
  </div>
</template>
