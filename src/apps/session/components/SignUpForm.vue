<!-- src/apps/session/components/SignUpForm.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { useAuth } from '@/shared/composables/useAuth';
import { Jurisdiction } from '@/schemas/models';
import { ref } from 'vue';

export interface Props {
  enabled?: boolean;
  jurisdiction?: Jurisdiction
  locale?: string;
}

withDefaults(defineProps<Props>(), {
  enabled: true,
  locale: 'en',
})

const { signup, isLoading, error, fieldError, clearErrors } = useAuth();

const { t } = useI18n();

const email = ref('');
const password = ref('');
const termsAgreed = ref(false);
const showPassword = ref(false);

const togglePasswordVisibility = () => {
  showPassword.value = !showPassword.value;
};

const handleSubmit = async () => {
  clearErrors();
  await signup(email.value, password.value, termsAgreed.value);
  // Navigation handled by useAuth composable
};
</script>

<template>
  <form
    @submit.prevent="handleSubmit"
    class="">
    <!-- Honeypot field for spam prevention -->
    <input
      type="text"
      name="skill"
      class="hidden"
      aria-hidden="true"
      aria-disabled="true"
      tabindex="-1"
      value="" />

    <!-- Error message -->
    <div
      v-if="error"
      class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
      role="alert"
      aria-live="assertive"
      aria-atomic="true">
      <div class="flex">
        <div class="shrink-0">
          <svg
            class="size-5 text-red-400"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true">
            <path
              fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
              clip-rule="evenodd" />
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-red-800 dark:text-red-200">
            {{ t('web.signup.error_title') }}
          </h3>
          <div class="mt-2 text-sm text-red-700 dark:text-red-300">
            <!-- Show specific field error if available, otherwise show generic error -->
            <p
              v-if="fieldError && fieldError[0] === 'password'"
              id="password-error"
              class="font-medium">
              {{ t('web.signup.password_error') }}: {{ fieldError[1] }}
            </p>
            <p
              v-else-if="fieldError && fieldError[0] === 'login'"
              id="email-error"
              class="font-medium">
              {{ t('web.signup.email_error') }}: {{ fieldError[1] }}
            </p>
            <p v-else id="form-error">
              {{ error }}
            </p>
          </div>
        </div>
      </div>
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
          :disabled="isLoading"
          focus
          tabindex="0"
          :aria-invalid="fieldError && fieldError[0] === 'login' ? 'true' : undefined"
          :aria-describedby="fieldError && fieldError[0] === 'login' ? 'email-error' : undefined"
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
            autocomplete="new-password"
            required
            :disabled="isLoading"
            tabindex="0"
            :aria-invalid="fieldError && fieldError[0] === 'password' ? 'true' : undefined"
            :aria-describedby="fieldError && fieldError[0] === 'password' ? 'password-error' : 'password-requirements'"
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
            :disabled="isLoading"
            :aria-label="showPassword ? t('web.COMMON.hide-password') : t('web.COMMON.show-password')"
            class="absolute inset-y-0 right-0 z-10 flex items-center pr-3 text-sm leading-5 disabled:opacity-50">
            <OIcon
              collection="heroicons"
              :name="showPassword ? 'outline-eye-off' : 'solid-eye'"
              size="5"
              class="text-gray-400"
              aria-hidden="true" />
          </button>
        </div>
        <!-- Password requirements (screen reader only) -->
        <span id="password-requirements" class="sr-only">
          {{ t('web.COMMON.password-requirements') }}
        </span>
      </div>
    </div>

    <!-- Terms checkbox -->
    <div class="mt-4 flex items-center justify-between">
      <div class="flex items-center text-lg">
        <input
          id="terms-agreement"
          name="agree"
          type="checkbox"
          required
          :disabled="isLoading"
          tabindex="0"
          class="size-4 rounded border-gray-300
                      text-brand-600
                      focus:ring-brand-500
                      disabled:cursor-not-allowed disabled:opacity-50
                      dark:border-gray-600
                      dark:bg-gray-700 dark:ring-offset-gray-800 dark:focus:ring-brand-500"
          v-model="termsAgreed" />
        <label
          for="terms-agreement"
          class="ml-2 block text-sm text-gray-900 dark:text-gray-300">
          {{ t('i-agree-to-the') }}
          <router-link
            to="/info/terms"
            class="font-medium text-brand-600 hover:text-brand-500
                     dark:text-brand-500 dark:hover:text-brand-400">
            {{ t('terms-of-service') }}
          </router-link>
          and
          <router-link
            to="/info/privacy"
            class="font-medium text-brand-600 hover:text-brand-500
                     dark:text-brand-500 dark:hover:text-brand-400">
            {{ t('privacy-policy') }}
          </router-link>
        </label>
      </div>
    </div>

    <!-- Submit button -->
    <div class="mt-5">
      <button
        type="submit"
        :disabled="isLoading"
        class="group relative flex w-full justify-center
                     rounded-md
                     border border-transparent
                     bg-brand-600 px-4 py-2
                     text-lg font-medium
                     text-white hover:bg-brand-700
                     focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
                     disabled:cursor-not-allowed disabled:opacity-50
                     dark:bg-brand-600 dark:hover:bg-brand-700 dark:focus:ring-offset-gray-800">
        <span v-if="isLoading">{{ t('web.COMMON.processing') || 'Processing...' }}</span>
        <span v-else>{{ t('create-account') }}</span>
      </button>
      <!-- Loading state announcement (screen reader only) -->
      <div
        v-if="isLoading"
        aria-live="polite"
        aria-atomic="true"
        class="sr-only">
        {{ t('web.COMMON.form-processing') }}
      </div>
    </div>
  </form>
</template>
