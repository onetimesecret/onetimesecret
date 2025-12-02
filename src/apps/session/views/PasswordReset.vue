<!-- src/views/auth/PasswordReset.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import AuthView from '@/apps/session/components/AuthView.vue';
import { useAuth } from '@/shared/composables/useAuth';
import { ref, computed } from 'vue';

export interface Props {
  enabled?: boolean;
  resetKey: string;
}

const props = withDefaults(defineProps<Props>(), {
  enabled: true,
  resetKey: '',
});

const { t } = useI18n();
const { resetPassword, isLoading, error, fieldError, clearErrors } = useAuth();

const newPassword = ref('');
const confirmPassword = ref('');

const hasValidResetKey = computed(() => props.resetKey && props.resetKey.trim() !== '');

const handleSubmit = async () => {
  if (!hasValidResetKey.value) {
    return;
  }
  clearErrors();
  await resetPassword(props.resetKey, newPassword.value, confirmPassword.value);
  // Navigation to /signin handled by useAuth composable on success
};
</script>

<template>
  <AuthView
    :heading="t('choose-a-new-password')"
    heading-id="password-reset-heading"
    :with-subheading="false"
    :hide-icon="true">
    <template #form>
      <p class="mb-6 text-gray-700 dark:text-gray-300">
        {{ t('please-enter-your-new-password-below-make-sure-i') }}
      </p>

      <!-- Missing reset key error -->
      <div
        v-if="!hasValidResetKey"
        class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
        role="alert">
        <p class="text-sm text-red-800 dark:text-red-200">
          Invalid or missing reset key. Please request a new password reset.
        </p>
      </div>

      <!-- Error messages -->
      <div
        v-if="error && hasValidResetKey"
        class="mb-4 rounded-md bg-red-50 p-4 dark:bg-red-900/20"
        role="alert"
        aria-live="assertive"
        aria-atomic="true">
        <!-- Generic error message -->
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ error }}
        </p>
        <!-- Field-specific error -->
        <p
          v-if="fieldError"
          id="password-error"
          class="mt-2 text-sm font-medium text-red-800 dark:text-red-200">
          {{ t(`web.auth.field-errors.${fieldError[0]}`) || fieldError[0] }}: {{ fieldError[1] }}
        </p>
      </div>

      <form
        v-if="hasValidResetKey"
        @submit.prevent="handleSubmit"
        id="passwordResetForm"
        class="space-y-4">
        <!-- Username field for accessibility -->
        <div class="hidden">
          <label
            class="mb-2 block text-sm font-bold text-gray-700 dark:text-gray-300"
            for="email">
            {{ t('email-address') }}
          </label>
          <input
            type="text"
            name="email"
            id="usernameField"
            autocomplete="email"
            class="focus:shadow-outline w-full appearance-none rounded border px-3 py-2 leading-tight text-gray-700 shadow focus:outline-none dark:bg-gray-700 dark:text-gray-300"
            placeholder="" />
        </div>

        <div>
          <label
            class="mb-2 block text-sm font-bold text-gray-700 dark:text-gray-300"
            for="passField">
            {{ t('new-password') }}
          </label>
          <input
            type="password"
            name="password"
            id="passField"
            required
            minlength="8"
            :disabled="isLoading"
            autocomplete="new-password"
            :aria-invalid="fieldError && (fieldError[0] === 'password' || fieldError[0] === 'password-confirm')"
            :aria-describedby="fieldError && (fieldError[0] === 'password' || fieldError[0] === 'password-confirm') ? 'password-error' : undefined"
            class="focus:shadow-outline w-full appearance-none rounded border px-3 py-2 leading-tight text-gray-700 shadow focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-300"
            placeholder=""
            v-model="newPassword" />
        </div>
        <div>
          <label
            class="mb-2 block text-sm font-bold text-gray-700 dark:text-gray-300"
            for="pass2Field">
            {{ t('confirm-password') }}
          </label>
          <input
            type="password"
            name="password-confirm"
            id="pass2Field"
            required
            minlength="8"
            :disabled="isLoading"
            autocomplete="new-password"
            :aria-invalid="fieldError && fieldError[0] === 'password-confirm'"
            :aria-describedby="fieldError && fieldError[0] === 'password-confirm' ? 'password-error' : undefined"
            class="focus:shadow-outline w-full appearance-none rounded border px-3 py-2 leading-tight text-gray-700 shadow focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-300"
            placeholder=""
            v-model="confirmPassword" />
        </div>
        <div class="flex items-center justify-between">
          <button
            type="submit"
            :disabled="isLoading"
            class="focus:shadow-outline rounded bg-brand-500 px-4 py-2 font-bold text-white transition duration-300 hover:bg-brand-700 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-600 dark:hover:bg-brand-800">
            <span v-if="isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
            <span v-else>{{ t('web.account.changePassword.updatePassword') }}</span>
          </button>
        </div>
      </form>
    </template>
    <template #footer>
      <router-link
        to="/signin"
        class="text-gray-600 transition-colors duration-200 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300">
        {{ t('back-to-sign-in') }}
      </router-link>
    </template>
  </AuthView>
</template>
