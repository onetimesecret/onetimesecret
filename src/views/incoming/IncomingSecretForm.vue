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
    validateTitle,
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
    validateTitle();
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
    form.value.title = '';
    form.value.secret = '';
    form.value.recipientId = '';
    form.value.passphrase = undefined;
    errors.value = {};
    secretContentRef.value?.clearTextarea();
  };
</script>

<template>
  <div class="min-h-screen bg-gray-50 py-8 dark:bg-slate-900">
    <div class="mx-auto max-w-3xl px-4 sm:px-6 lg:px-8">
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
        v-if="isLoading"
        :message="$t('web.incoming.loading_config')" />

      <!-- Error State -->
      <EmptyState v-else-if="loadError">
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

          <!-- Optional Passphrase -->
          <div>
            <label
              for="secret-passphrase"
              class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ $t('web.incoming.passphrase_label') }}
              <span class="text-sm font-normal text-gray-500 dark:text-gray-400">
                ({{ $t('web.incoming.optional') }})
              </span>
            </label>

            <input
              id="secret-passphrase"
              v-model="form.passphrase"
              type="password"
              :disabled="isSubmitting"
              :placeholder="$t('web.incoming.passphrase_placeholder')"
              class="block w-full rounded-lg border border-gray-200 px-4 py-3 text-base text-gray-900 transition-all duration-200 placeholder:text-gray-400 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 disabled:bg-gray-50 disabled:text-gray-500 dark:border-gray-700 dark:bg-slate-800 dark:text-white dark:placeholder:text-gray-500 dark:focus:border-blue-400 dark:focus:ring-blue-400" />

            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{ $t('web.incoming.passphrase_hint') }}
            </p>
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
  </div>
</template>
