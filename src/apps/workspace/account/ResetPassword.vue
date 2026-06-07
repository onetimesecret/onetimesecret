<!-- src/apps/workspace/account/ResetPassword.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import SettingsLayout from '@/apps/workspace/layouts/SettingsLayout.vue';
import { useAuth } from '@/shared/composables/useAuth';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { ref, computed } from 'vue';

const { t } = useI18n();
const bootstrapStore = useBootstrapStore();
const { requestPasswordReset, isLoading, error, clearErrors } = useAuth();

const email = computed(() => bootstrapStore.email ?? '');
const successMessage = ref('');

const handleSubmit = async () => {
  clearErrors();
  successMessage.value = '';

  const success = await requestPasswordReset(email.value);
  if (success) {
    successMessage.value = t('web.auth.passwordReset.emailSent');
  }
};
</script>

<template>
  <SettingsLayout>
    <div class="mx-auto max-w-2xl">
      <div class="bg-white shadow dark:bg-gray-800 sm:rounded-lg">
        <div class="px-4 py-5 sm:p-6">
          <h3 class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
            {{ t('web.auth.password_reset_request.title') }}
          </h3>
          <div class="mt-2 max-w-xl text-sm text-gray-500 dark:text-gray-400">
            <p>{{ t('web.auth.password_reset_request.description') }}</p>
          </div>

          <!-- Success message -->
          <div
            v-if="successMessage"
            class="mt-4 rounded-md bg-green-50 p-4 dark:bg-green-900/20"
            role="alert"
            data-testid="password-reset-success">
            <p class="text-sm text-green-800 dark:text-green-200">
              {{ successMessage }}
            </p>
          </div>

          <!-- Error message -->
          <div
            v-if="error"
            class="mt-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
            role="alert"
            data-testid="password-reset-error">
            <p class="text-sm text-red-800 dark:text-red-200">
              {{ error }}
            </p>
          </div>

          <form
            @submit.prevent="handleSubmit"
            class="mt-5 space-y-4">
            <div>
              <label
                for="reset-email"
                class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.COMMON.email_address') }}
              </label>
              <div class="mt-1">
                <input
                  id="reset-email"
                  type="email"
                  name="email"
                  readonly
                  :value="email"
                  data-testid="password-reset-email-input"
                  class="block w-full rounded-md border-gray-300 bg-gray-50 shadow-sm dark:border-gray-600 dark:bg-gray-700/50 dark:text-gray-300 sm:text-sm" />
              </div>
            </div>

            <div class="flex justify-end">
              <button
                type="submit"
                :disabled="isLoading"
                data-testid="password-reset-request-submit"
                class="inline-flex justify-center rounded-md border border-transparent bg-brand-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-600 dark:hover:bg-brand-700">
                <span v-if="isLoading">{{ t('web.COMMON.processing') }}</span>
                <span v-else>{{ t('web.auth.password_reset_request.button') }}</span>
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  </SettingsLayout>
</template>
