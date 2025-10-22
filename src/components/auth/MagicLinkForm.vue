<!-- src/components/auth/MagicLinkForm.vue -->
<script setup lang="ts">
import { ref } from 'vue';
import { useMagicLink } from '@/composables/useMagicLink';

const { requestMagicLink, sent, isLoading, error, clearState } = useMagicLink();

const email = ref('');

const handleSubmit = async () => {
  await requestMagicLink(email.value);
};

const handleTryAgain = () => {
  clearState();
  email.value = '';
};
</script>

<template>
  <!-- Success state - magic link sent -->
  <div
    v-if="sent"
    class="mt-8 space-y-6">
    <div class="rounded-md bg-green-50 p-6 text-center dark:bg-green-900/20">
      <svg
        class="mx-auto size-12 text-green-600 dark:text-green-400"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        aria-hidden="true">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M3 19v-8.93a2 2 0 01.89-1.664l7-4.666a2 2 0 012.22 0l7 4.666A2 2 0 0121 10.07V19M3 19a2 2 0 002 2h14a2 2 0 002-2M3 19l6.75-4.5M21 19l-6.75-4.5M3 10l6.75 4.5M21 10l-6.75 4.5m0 0l-1.14.76a2 2 0 01-2.22 0l-1.14-.76" />
      </svg>
      <h3 class="mt-4 text-lg font-medium text-green-900 dark:text-green-100">
        {{ $t('auth.magicLink.checkEmail') }}
      </h3>
      <p class="mt-2 text-sm text-green-800 dark:text-green-200">
        {{ $t('auth.magicLink.sentTo', { email }) }}
      </p>
      <p class="mt-3 text-xs text-green-700 dark:text-green-300">
        {{ $t('auth.magicLink.linkExpiresIn') }}
      </p>
    </div>

    <button
      type="button"
      @click="handleTryAgain"
      class="text-sm text-brand-600 transition duration-300 ease-in-out hover:underline dark:text-brand-400">
      {{ $t('auth.magicLink.tryDifferentEmail') }}
    </button>
  </div>

  <!-- Request form -->
  <form
    v-else
    @submit.prevent="handleSubmit"
    class="mt-8 space-y-6">
    <!-- Error message -->
    <div
      v-if="error"
      class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
      role="alert">
      <p class="text-sm text-red-800 dark:text-red-200">
        {{ error }}
      </p>
    </div>

    <!-- Description -->
    <div class="text-center">
      <p class="text-sm text-gray-600 dark:text-gray-400">
        {{ $t('auth.magicLink.description') }}
      </p>
    </div>

    <!-- Email input -->
    <div>
      <label
        for="magic-link-email"
        class="sr-only">{{ $t('email-address') }}</label>
      <input
        id="magic-link-email"
        name="email"
        type="email"
        autocomplete="email"
        required
        :disabled="isLoading"
        v-model="email"
        class="relative block w-full appearance-none rounded-md
                      border
                      border-gray-300 px-3
                      py-2 text-lg
                      text-gray-900 placeholder:text-gray-500
                      focus:z-10 focus:border-brand-500 focus:outline-none focus:ring-brand-500
                      disabled:cursor-not-allowed disabled:opacity-50
                      dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400
                      dark:focus:border-brand-500 dark:focus:ring-brand-500"
        :placeholder="$t('auth.magicLink.emailPlaceholder')" />
    </div>

    <!-- Submit button -->
    <div>
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
        <span
          v-if="isLoading"
          class="flex items-center">
          <svg
            class="-ml-1 mr-3 size-5 animate-spin text-white"
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
          {{ $t('web.COMMON.processing') }}
        </span>
        <span v-else>{{ $t('auth.magicLink.sendLink') }}</span>
      </button>
    </div>

    <!-- Help text -->
    <div class="text-center">
      <p class="text-xs text-gray-500 dark:text-gray-400">
        {{ $t('auth.magicLink.noPasswordNeeded') }}
      </p>
    </div>
  </form>
</template>
