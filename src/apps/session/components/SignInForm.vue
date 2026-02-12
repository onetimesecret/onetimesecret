<!-- src/apps/session/components/SignInForm.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import LockoutAlert from '@/apps/session/components/LockoutAlert.vue';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useAuth } from '@/shared/composables/useAuth';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { ref } from 'vue';
import { useRoute } from 'vue-router';

const { t } = useI18n();
const route = useRoute();

export interface Props {
  enabled?: boolean;
  locale?: string;
}

withDefaults(defineProps<Props>(), {
  enabled: true,
  locale: 'en',
})

const bootstrapStore = useBootstrapStore();
const { login, isLoading, error, lockoutStatus, clearErrors } = useAuth();

// Prefill email from query param (e.g., from invitation flow)
const emailFromQuery = typeof route.query.email === 'string' ? route.query.email : '';
const email = ref(emailFromQuery);
const password = ref('');
const rememberMe = ref(false);
const showPassword = ref(false);

const togglePasswordVisibility = () => {
  showPassword.value = !showPassword.value;
};

const isSubmitting = ref(false);

const handleSubmit = async () => {
  if (isSubmitting.value) return;
  isSubmitting.value = true;
  try {
    clearErrors();
    await bootstrapStore.refresh();
    await login(email.value, password.value, rememberMe.value);
    // Navigation handled by useAuth composable
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <form
    @submit.prevent="handleSubmit"
    class="space-y-6">
    <!-- Lockout alert (takes precedence over generic error) -->
    <LockoutAlert :lockout="lockoutStatus" />

    <!-- Generic error message (shown when not a lockout error) -->
    <div
      v-if="error && !lockoutStatus"
      id="signin-error"
      class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
      role="alert"
      aria-live="assertive"
      aria-atomic="true">
      <p class="text-sm text-red-800 dark:text-red-200">
        {{ error }}
      </p>
    </div>

    <div class="space-y-4">
      <!-- Email field -->
      <div>
        <label
          for="email-address"
          class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.COMMON.field_email') }}
        </label>
        <input
          id="email-address"
          name="email"
          type="email"
          autocomplete="email"
          required
          :disabled="isSubmitting || isLoading"
          :aria-invalid="error && !lockoutStatus ? 'true' : undefined"
          :aria-describedby="error && !lockoutStatus ? 'signin-error' : undefined"
          class="block w-full appearance-none rounded-md
                      border
                      border-gray-300 px-3
                      py-2 text-lg
                      text-gray-900 placeholder:text-gray-500
                      focus:border-brand-500 focus:outline-none focus:ring-brand-500
                      disabled:cursor-not-allowed disabled:opacity-50
                      dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400
                      dark:focus:border-brand-500 dark:focus:ring-brand-500"
          :placeholder="t('web.COMMON.email_placeholder')"
          v-model="email" />
      </div>

      <!-- Password input with visibility toggle -->
      <div>
        <label
          for="password"
          class="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
          {{ t('web.COMMON.field_password') }}
        </label>
        <div class="relative">
          <input
            id="password"
            :type="showPassword ? 'text' : 'password'"
            name="password"
            autocomplete="current-password"
            required
            :disabled="isSubmitting || isLoading"
            :aria-invalid="error && !lockoutStatus ? 'true' : undefined"
            :aria-describedby="error && !lockoutStatus ? 'signin-error' : undefined"
            class="block w-full appearance-none rounded-md
                   border
                   border-gray-300 px-3
                   py-2 pr-10 text-lg
                   text-gray-900 placeholder:text-gray-500
                   focus:border-brand-500 focus:outline-none focus:ring-brand-500
                   disabled:cursor-not-allowed disabled:opacity-50
                   dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400
                   dark:focus:border-brand-500 dark:focus:ring-brand-500"
            :placeholder="t('web.COMMON.password_placeholder')"
            v-model="password" />
          <button
            type="button"
            @click="togglePasswordVisibility"
            :disabled="isSubmitting || isLoading"
            :aria-label="showPassword ? t('web.COMMON.hide_password') : t('web.COMMON.show_password')"
            class="absolute inset-y-0 right-0 z-10 flex items-center pr-3 text-sm leading-5 disabled:opacity-50">
            <OIcon
              collection="heroicons"
              :name="showPassword ? 'outline-eye-off' : 'solid-eye'"
              size="5"
              class="text-gray-400"
              aria-hidden="true" />
          </button>
        </div>
      </div>
    </div>

    <!-- Remember me and forgot password -->
    <div class="mt-3 flex items-center justify-between">
      <div class="flex items-center">
        <input
          id="remember-me"
          name="remember-me"
          type="checkbox"
          :disabled="isSubmitting || isLoading"
          aria-describedby="remember-me-description"
          class="size-4 rounded border-gray-300
                      text-brand-600
                      focus:ring-brand-500
                      disabled:cursor-not-allowed disabled:opacity-50
                      dark:border-gray-600
                      dark:bg-gray-700 dark:ring-offset-gray-800 dark:focus:ring-brand-500"
          v-model="rememberMe" />
        <label
          for="remember-me"
          class="ml-2 block text-sm text-gray-900 dark:text-gray-300">
          {{ t('web.login.remember_me') }}
        </label>
        <span id="remember-me-description" class="sr-only">
          {{ t('web.COMMON.remember_me_description') }}
        </span>
      </div>

      <router-link
        to="/forgot"
        class="text-sm text-gray-600 transition duration-300 ease-in-out hover:underline dark:text-gray-400"
        :aria-label="t('web.login.forgot_your_password')">
        {{ t('web.login.forgot_your_password') }}
      </router-link>
    </div>

    <!-- Submit button -->
    <div class="mt-5">
      <button
        type="submit"
        :disabled="isSubmitting || isLoading"
        class="group relative flex w-full justify-center
                     rounded-md
                     border border-transparent
                     bg-brand-600 px-4 py-2
                     text-lg font-medium
                     text-white hover:bg-brand-700
                     focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
                     disabled:cursor-not-allowed disabled:opacity-50
                     dark:bg-brand-600 dark:hover:bg-brand-700 dark:focus:ring-offset-gray-800">
        <span v-if="isSubmitting || isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
        <span v-else>{{ t('web.login.button_sign_in') }}</span>
      </button>
      <!-- Loading state announcement (screen reader only) -->
      <div
        v-if="isSubmitting || isLoading"
        aria-live="polite"
        aria-atomic="true"
        class="sr-only">
        {{ t('web.COMMON.form_processing') }}
      </div>
    </div>
  </form>
</template>
