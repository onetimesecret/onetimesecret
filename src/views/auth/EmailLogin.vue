<!-- eslint-disable vue/multi-word-component-names -->
<!-- src/views/auth/EmailLogin.vue -->
<script setup lang="ts">
import { onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useMagicLink } from '@/composables/useMagicLink';

const route = useRoute();
const { verifyMagicLink, isLoading, error } = useMagicLink();

const hasError = ref(false);

onMounted(async () => {
  const key = route.query.key as string;

  if (!key) {
    hasError.value = true;
    return;
  }

  const success = await verifyMagicLink(key);
  if (!success) {
    hasError.value = true;
  }
});
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-gray-50 px-4 py-12 dark:bg-gray-900 sm:px-6 lg:px-8">
    <div class="w-full max-w-md space-y-8">
      <!-- Loading state -->
      <div
        v-if="isLoading"
        class="text-center">
        <svg
          class="mx-auto size-16 animate-spin text-brand-600 dark:text-brand-400"
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
        <h2 class="mt-6 text-xl font-medium text-gray-900 dark:text-white">
          {{ $t('web.auth.magicLink.signingYouIn') }}
        </h2>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ $t('web.auth.magicLink.pleaseWait') }}
        </p>
      </div>

      <!-- Error state -->
      <div
        v-else-if="hasError"
        class="rounded-md bg-red-50 p-6 dark:bg-red-900/20">
        <div class="flex">
          <svg
            class="size-6 text-red-400"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            aria-hidden="true">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
          <div class="ml-3">
            <h3 class="text-sm font-medium text-red-800 dark:text-red-200">
              {{ $t('web.auth.magicLink.error') }}
            </h3>
            <div class="mt-2 text-sm text-red-700 dark:text-red-300">
              <p>{{ error || $t('web.auth.magicLink.invalidLink') }}</p>
            </div>
            <div class="mt-4">
              <router-link
                to="/signin"
                class="text-sm font-medium text-red-700 hover:text-red-600 dark:text-red-300 dark:hover:text-red-200">
                {{ $t('web.auth.magicLink.backToSignin') }}
              </router-link>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
