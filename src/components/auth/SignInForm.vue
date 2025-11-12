<!-- src/components/auth/SignInForm.vue -->

<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import LockoutAlert from '@/components/auth/LockoutAlert.vue';
import { useAuth } from '@/composables/useAuth';
import { ref } from 'vue';

export interface Props {
  enabled?: boolean;
  locale?: string;
}

withDefaults(defineProps<Props>(), {
  enabled: true,
  locale: 'en',
})

const { login, isLoading, error, lockoutStatus, clearErrors } = useAuth();

const email = ref('');
const password = ref('');
const rememberMe = ref(false);
const showPassword = ref(false);

const togglePasswordVisibility = () => {
  showPassword.value = !showPassword.value;
};

const handleSubmit = async () => {
  clearErrors();
  await login(email.value, password.value, rememberMe.value);
  // Navigation handled by useAuth composable
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
      class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
      role="alert">
      <p class="text-sm text-red-800 dark:text-red-200">
        {{ error }}
      </p>
    </div>

    <div class="-space-y-px rounded-md text-lg shadow-sm">
      <!-- Email field -->
      <div>
        <label
          for="email-address"
          class="sr-only">{{ $t('email-address') }}</label>
        <input
          id="email-address"
          name="email"
          type="email"
          autocomplete="email"
          required
          :disabled="isLoading"
          class="relative block w-full appearance-none rounded-none rounded-t-md
                      border
                      border-gray-300 px-3
                      py-2 text-lg
                      text-gray-900 placeholder:text-gray-500
                      focus:z-10 focus:border-brand-500 focus:outline-none focus:ring-brand-500
                      disabled:opacity-50 disabled:cursor-not-allowed
                      dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400
                      dark:focus:border-brand-500 dark:focus:ring-brand-500"
          :placeholder="$t('email-address')"
          v-model="email"
        />
      </div>

      <!-- Password input with visibility toggle -->
      <div class="relative">
        <label
          for="password"
          class="sr-only">{{ $t('web.COMMON.field_password') }}</label>
        <input
          id="password"
          :type="showPassword ? 'text' : 'password'"
          name="password"
          autocomplete="current-password"
          required
          :disabled="isLoading"
          class="relative block w-full appearance-none rounded-none rounded-b-md
                 border
                 border-gray-300 px-3
                 py-2 pr-10 text-lg
                 text-gray-900 placeholder:text-gray-500
                 focus:z-10 focus:border-brand-500 focus:outline-none focus:ring-brand-500
                 disabled:opacity-50 disabled:cursor-not-allowed
                 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400
                 dark:focus:border-brand-500 dark:focus:ring-brand-500"
          :placeholder="$t('web.COMMON.field_password')"
          v-model="password"
        />
        <button
          type="button"
          @click="togglePasswordVisibility"
          :disabled="isLoading"
          class="absolute inset-y-0 right-0 z-10 flex items-center pr-3 text-sm leading-5 disabled:opacity-50">
            <OIcon
              collection="heroicons"
              :name="showPassword ? 'outline-eye-off' : 'solid-eye'"
              size="20"
              class="size-5 text-gray-400"
              aria-hidden="true" />
        </button>
      </div>
    </div>

    <!-- Remember me and forgot password -->
    <div class="mt-3 flex items-center justify-between">
      <div class="flex items-center">
        <input
          id="remember-me"
          name="remember-me"
          type="checkbox"
          :disabled="isLoading"
          class="size-4 rounded border-gray-300
                      text-brand-600
                      focus:ring-brand-500
                      disabled:opacity-50 disabled:cursor-not-allowed
                      dark:border-gray-600
                      dark:bg-gray-700 dark:ring-offset-gray-800 dark:focus:ring-brand-500"
          v-model="rememberMe"
        />
        <label
          for="remember-me"
          class="ml-2 block text-sm text-gray-900 dark:text-gray-300">
          {{ $t('web.login.remember_me') }}
        </label>
      </div>

      <router-link
        to="/forgot"
        class="text-sm text-gray-600 transition duration-300 ease-in-out hover:underline dark:text-gray-400"
        :aria-label="$t('forgot-password')">
        {{ $t('web.login.forgot_your_password') }}
      </router-link>
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
                     disabled:opacity-50 disabled:cursor-not-allowed
                     dark:bg-brand-600 dark:hover:bg-brand-700 dark:focus:ring-offset-gray-800">
        <span v-if="isLoading">{{ $t('web.COMMON.processing') || 'Processing...' }}</span>
        <span v-else>{{ $t('web.login.button_sign_in') }}</span>
      </button>
    </div>
  </form>
</template>
