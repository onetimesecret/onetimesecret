<!-- src/apps/workspace/account/RecoveryCodes.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import SettingsLayout from '@/shared/components/layout/SettingsLayout.vue';
  import { useMfa } from '@/shared/composables/useMfa';
  import { ref, onMounted, computed } from 'vue';

  const { t } = useI18n();
  const { mfaStatus, isLoading, error, fetchMfaStatus, generateNewRecoveryCodes, clearError } =
    useMfa();

  const showGenerateConfirm = ref(false);
  const regeneratePassword = ref('');

  onMounted(async () => {
    // Fetch MFA status to get the recovery codes count
    // We don't fetch actual codes - just display the count
    await fetchMfaStatus();
  });

  // Check if MFA is enabled
  const mfaEnabled = computed(() => mfaStatus.value?.enabled || false);

  // Check if there are recovery codes remaining
  const hasRecoveryCodes = computed(() => (mfaStatus.value?.recovery_codes_remaining ?? 0) > 0);

  // Show generate confirmation modal
  const showGenerateModal = () => {
    regeneratePassword.value = '';
    showGenerateConfirm.value = true;
  };

  // Cancel generate confirmation
  const cancelGenerate = () => {
    showGenerateConfirm.value = false;
    regeneratePassword.value = '';
  };

  // Generate new codes
  const handleGenerateNew = async () => {
    if (!regeneratePassword.value) return;

    // Clear any previous errors
    clearError();

    // Generate new codes - the composable sets recoveryCodes.value directly
    await generateNewRecoveryCodes(regeneratePassword.value);

    // If no error occurred, the codes were generated successfully
    // Close modal and refresh (recoveryCodes.value is already set by the composable)
    if (!error.value) {
      showGenerateConfirm.value = false;
      regeneratePassword.value = '';
      await fetchMfaStatus();
    }
    // If error exists, modal stays open with error displayed
  };
</script>

<template>
  <SettingsLayout>
    <div>
      <div class="mb-6">
        <h1 class="text-3xl font-bold dark:text-white">
          {{ t('web.auth.recovery-codes.title') }}
        </h1>
        <p class="mt-2 text-gray-600 dark:text-gray-400">
          {{ t('web.auth.recovery-codes.description') }}
        </p>
      </div>

      <!-- MFA not enabled warning -->
      <div
        v-if="!mfaEnabled && !isLoading"
        class="rounded-lg border border-yellow-200 bg-yellow-50 p-6 dark:border-yellow-800 dark:bg-yellow-900/20">
        <div class="flex items-start gap-3">
          <i class="fas fa-exclamation-triangle text-2xl text-yellow-600 dark:text-yellow-400"></i>
          <div>
            <h2 class="font-semibold text-yellow-800 dark:text-yellow-300">
              Two-Factor Authentication is not enabled
            </h2>
            <p class="mt-1 text-sm text-yellow-700 dark:text-yellow-400">
              Recovery codes are only available when two-factor authentication is enabled.
            </p>
            <router-link
              to="/account/settings/security/mfa"
              class="mt-3 inline-block text-sm font-medium text-yellow-800 hover:text-yellow-900 dark:text-yellow-300 dark:hover:text-yellow-200">
              Enable Two-Factor Authentication →
            </router-link>
          </div>
        </div>
      </div>

      <!-- Loading state -->
      <div
        v-else-if="isLoading"
        class="flex items-center justify-center py-12">
        <i class="fas fa-spinner fa-spin mr-2 text-2xl text-gray-400"></i>
        <span class="text-gray-600 dark:text-gray-400">Loading recovery codes...</span>
      </div>

      <!-- Error state -->
      <div
        v-else-if="error"
        class="rounded-lg bg-red-50 p-4 dark:bg-red-900/20"
        role="alert">
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ error }}
        </p>
      </div>

      <!-- Recovery codes status (shows count, not actual codes) -->
      <div
        v-else-if="hasRecoveryCodes"
        class="space-y-6">
        <!-- Status info -->
        <div class="rounded-lg bg-blue-50 p-4 dark:bg-blue-900/20">
          <div class="flex items-start gap-3">
            <i class="fas fa-shield-alt text-blue-600 dark:text-blue-400"></i>
            <div class="text-sm text-blue-800 dark:text-blue-300">
              <p class="font-semibold">
                {{
                  t('web.auth.recovery-codes.remaining', {
                    count: mfaStatus?.recovery_codes_remaining ?? 0,
                  })
                }}
              </p>
              <p class="mt-1">
                Each code can only be used once. Generate new codes if you're running low.
              </p>
            </div>
          </div>
        </div>

        <!-- Generate new codes -->
        <div
          class="rounded-lg border border-gray-200 bg-gray-50 p-6 dark:border-gray-700 dark:bg-gray-800">
          <h3 class="mb-2 font-semibold dark:text-white">
            {{ t('web.auth.recovery-codes.generate-new') }}
          </h3>
          <p class="mb-4 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.auth.recovery-codes.generate-new-warning') }}
          </p>
          <button
            @click="showGenerateModal"
            type="button"
            class="rounded-md border border-yellow-300 px-4 py-2 text-sm font-medium text-yellow-700 hover:bg-yellow-50 focus:outline-none focus:ring-2 focus:ring-yellow-500 focus:ring-offset-2 dark:border-yellow-600 dark:text-yellow-400 dark:hover:bg-yellow-900/20">
            <i class="fas fa-sync mr-2"></i>
            {{ t('web.auth.recovery-codes.generate-new') }}
          </button>
        </div>
      </div>

      <!-- No codes available -->
      <div
        v-else
        class="rounded-lg border border-gray-200 bg-gray-50 p-6 text-center dark:border-gray-700 dark:bg-gray-800">
        <p class="text-gray-600 dark:text-gray-400">
          {{ t('web.auth.recovery-codes.none-remaining') }}
        </p>
        <button
          @click="showGenerateModal"
          type="button"
          class="mt-4 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2">
          {{ t('web.auth.recovery-codes.generate-new') }}
        </button>
      </div>

      <!-- Generate confirmation modal -->
      <div
        v-if="showGenerateConfirm"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
        @click.self="cancelGenerate">
        <div
          class="mx-4 max-w-md rounded-lg bg-white p-6 shadow-xl dark:bg-gray-800"
          role="dialog"
          aria-modal="true"
          aria-labelledby="regenerate-codes-title">
          <div class="mb-4 flex items-center">
            <i class="fas fa-exclamation-triangle mr-3 text-2xl text-yellow-500"></i>
            <h3
              id="regenerate-codes-title"
              class="text-lg font-semibold dark:text-white">
              {{ t('web.auth.recovery-codes.generate-new') }}
            </h3>
          </div>
          <p class="mb-4 text-sm text-gray-600 dark:text-gray-400">
            {{ t('web.auth.recovery-codes.generate-new-warning') }}
          </p>

          <form @submit.prevent="handleGenerateNew">
            <!-- Password input -->
            <div class="mb-4">
              <label
                for="regenerate-password"
                class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.auth.mfa.password-confirmation') }}
              </label>
              <input
                id="regenerate-password"
                v-model="regeneratePassword"
                type="password"
                autocomplete="current-password"
                :disabled="isLoading"
                :placeholder="t('web.auth.mfa.password-placeholder')"
                class="block w-full appearance-none rounded-md border border-gray-300 px-3 py-2 placeholder:text-gray-400 focus:border-brand-500 focus:outline-none focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                {{ t('web.auth.mfa.password-reason') }}
              </p>
            </div>

            <!-- Error message -->
            <div
              v-if="error"
              class="mb-4 rounded-md bg-red-50 p-3 dark:bg-red-900/20"
              role="alert">
              <p class="text-sm text-red-800 dark:text-red-200">
                {{ error }}
              </p>
            </div>

            <!-- Action buttons -->
            <div class="flex justify-end gap-3">
              <button
                @click="cancelGenerate"
                type="button"
                :disabled="isLoading"
                class="rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700">
                {{ t('web.COMMON.word_cancel') }}
              </button>
              <button
                type="submit"
                :disabled="isLoading || !regeneratePassword"
                class="rounded-md bg-yellow-600 px-4 py-2 text-sm font-medium text-white hover:bg-yellow-700 focus:outline-none focus:ring-2 focus:ring-yellow-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
                <span v-if="isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
                <span v-else>{{ t('web.auth.recovery-codes.generate-new') }}</span>
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  </SettingsLayout>
</template>
