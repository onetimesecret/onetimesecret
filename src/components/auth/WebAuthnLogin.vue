<!-- src/components/auth/WebAuthnLogin.vue -->
<script setup lang="ts">
import { useWebAuthn } from '@/composables/useWebAuthn';

const { supported, authenticateWebAuthn, isLoading, error } = useWebAuthn();

const handleWebAuthnLogin = async () => {
  await authenticateWebAuthn();
};
</script>

<template>
  <div class="mt-8 space-y-6">
    <!-- Not supported warning -->
    <div
      v-if="!supported"
      class="rounded-md bg-yellow-50 p-4 dark:bg-yellow-900/20"
      role="alert">
      <div class="flex">
        <svg
          class="size-5 text-yellow-400"
          fill="currentColor"
          viewBox="0 0 20 20"
          aria-hidden="true">
          <path
            fill-rule="evenodd"
            d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
            clip-rule="evenodd" />
        </svg>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800 dark:text-yellow-200">
            {{ $t('web.auth.webauthn.notSupported') }}
          </h3>
          <p class="mt-2 text-sm text-yellow-700 dark:text-yellow-300">
            {{ $t('web.auth.webauthn.requiresModernBrowser') }}
          </p>
        </div>
      </div>
    </div>

    <!-- Error message -->
    <div
      v-if="error"
      class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
      role="alert">
      <p class="text-sm text-red-800 dark:text-red-200">
        {{ error }}
      </p>
    </div>

    <!-- WebAuthn button (enabled state) -->
    <div v-if="supported">
      <!-- Description -->
      <div class="mb-6 text-center">
        <p class="text-sm text-gray-600 dark:text-gray-400">
          {{ $t('web.auth.webauthn.description') }}
        </p>
      </div>

      <button
        @click="handleWebAuthnLogin"
        :disabled="isLoading"
        class="group relative flex w-full items-center justify-center
                     rounded-md
                     border-2 border-brand-300
                     bg-white px-4 py-3
                     text-lg font-medium
                     text-brand-700 hover:bg-brand-50
                     focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
                     disabled:cursor-not-allowed disabled:opacity-50
                     dark:border-brand-700 dark:bg-gray-800 dark:text-brand-400 dark:hover:bg-gray-750
                     dark:focus:ring-offset-gray-800">
        <!-- Icon -->
        <svg
          v-if="!isLoading"
          class="mr-3 size-6 text-brand-600 dark:text-brand-400"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
          aria-hidden="true">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
        </svg>

        <!-- Loading spinner -->
        <svg
          v-if="isLoading"
          class="-ml-1 mr-3 size-5 animate-spin text-brand-600 dark:text-brand-400"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          aria-hidden="true">
          <circle
            class="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            stroke-width="4"/>
          <path
            class="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"/>
        </svg>

        <span v-if="isLoading">{{ $t('web.auth.webauthn.processing') }}</span>
        <span v-else>{{ $t('web.auth.webauthn.signIn') }}</span>
      </button>

      <!-- Help text -->
      <div class="mt-4 text-center">
        <p class="text-xs text-gray-500 dark:text-gray-400">
          {{ $t('web.auth.webauthn.supportedMethods') }}
        </p>
      </div>
    </div>
  </div>
</template>
