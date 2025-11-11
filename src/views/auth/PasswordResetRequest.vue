<!-- eslint-disable vue/multi-word-component-names -->
<!-- src/views/auth/PasswordResetRequest.vue -->

<script setup lang="ts">
import AuthView from '@/components/auth/AuthView.vue';
import { useAuth } from '@/composables/useAuth';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

export interface Props {
  enabled?: boolean;
}

withDefaults(defineProps<Props>(), {
  enabled: true,
})

const { t } = useI18n();

const { requestPasswordReset, isLoading, error, clearErrors } = useAuth();

const email = ref('');
const successMessage = ref('');

const handleSubmit = async () => {
  clearErrors();
  successMessage.value = '';

  const success = await requestPasswordReset(email.value);
  if (success) {
    successMessage.value = t('web.auth.passwordReset.emailSent');
    email.value = ''; // Clear the form
  }
};
</script>

<template>
  <AuthView
    :heading="t('request-password-reset')"
    heading-id="password-reset-request-heading"
    :with-subheading="false">
    <template #form>
      <p class="mb-6 text-gray-700 dark:text-gray-300">
        {{ t('enter-your-email-address-below-and-well-send-you') }}
      </p>

      <!-- Success message -->
      <div
        v-if="successMessage"
        class="mb-4 rounded-md bg-green-50 p-4 dark:bg-green-900/20"
        role="alert">
        <p class="text-sm text-green-800 dark:text-green-200">
          {{ successMessage }}
        </p>
      </div>

      <!-- Error message -->
      <div
        v-if="error"
        class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
        role="alert">
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ error }}
        </p>
      </div>

      <form
        @submit.prevent="handleSubmit"
        id="resetRequestForm"
        class="space-y-4">
        <div>
          <label
            class="mb-2 block text-sm font-bold text-gray-700 dark:text-gray-300"
            for="custidField">
            {{ t('email-address') }}
          </label>
          <input
            type="email"
            name="email"
            id="custidField"
            required
            :disabled="isLoading"
            class="focus:shadow-outline w-full appearance-none rounded border px-3 py-2 leading-tight text-gray-700 shadow focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed dark:bg-gray-700 dark:text-gray-300"
            v-model="email"
            :placeholder="t('web.COMMON.email_placeholder')"
          />
        </div>
        <div class="flex items-center justify-between">
          <button
            type="submit"
            :disabled="isLoading"
            class="focus:shadow-outline rounded bg-brand-500 px-4 py-2 font-bold text-white transition duration-300 hover:bg-brand-700 focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed dark:bg-brand-600 dark:hover:bg-brand-800">
            <span v-if="isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
            <span v-else>{{ t('request-reset') }}</span>
          </button>
        </div>
      </form>
    </template>
    <template #footer>
      <router-link
        to="/signin"
        class="font-medium text-brand-600 transition-colors duration-200 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
        {{ t('back-to-sign-in') }}
      </router-link>
    </template>
  </AuthView>
</template>
