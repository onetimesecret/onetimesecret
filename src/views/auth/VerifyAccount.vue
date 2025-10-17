<!-- src/views/auth/VerifyAccount.vue -->
<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAuth } from '@/composables/useAuth';
import BaseLayout from '@/components/BaseLayout.vue';

const route = useRoute();
const { verifyAccount, isLoading, error, fieldError } = useAuth();

const verificationKey = ref<string>('');
const verificationComplete = ref(false);
const verificationSuccess = ref(false);

onMounted(async () => {
  // Extract key from route params
  verificationKey.value = route.params.key as string;

  // Auto-submit verification on mount
  if (verificationKey.value) {
    const success = await verifyAccount(verificationKey.value);
    verificationComplete.value = true;
    verificationSuccess.value = success;
  }
});
</script>

<template>
  <BaseLayout>
    <div class="flex min-h-full items-center justify-center px-4 py-12 sm:px-6 lg:px-8">
      <div class="w-full max-w-md space-y-8">
        <div>
          <h2 class="mt-6 text-center text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
            {{ $t('web.auth.verify.title') }}
          </h2>
        </div>

        <!-- Loading state -->
        <div
          v-if="isLoading"
          class="rounded-md bg-blue-50 p-4 dark:bg-blue-900/20">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg
                class="h-5 w-5 animate-spin text-blue-400"
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
            </div>
            <div class="ml-3">
              <p class="text-sm text-blue-800 dark:text-blue-200">
                {{ $t('web.COMMON.processing') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Success state -->
        <div
          v-else-if="verificationComplete && verificationSuccess"
          class="rounded-md bg-green-50 p-4 dark:bg-green-900/20">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg
                class="h-5 w-5 text-green-400"
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
                aria-hidden="true">
                <path
                  fill-rule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z"
                  clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <p class="text-sm text-green-800 dark:text-green-200">
                {{ $t('web.auth.verify.success') }}
              </p>
              <p class="mt-2 text-sm text-green-700 dark:text-green-300">
                {{ $t('web.COMMON.redirecting') }}
              </p>
            </div>
          </div>
        </div>

        <!-- Error state -->
        <div
          v-else-if="verificationComplete && !verificationSuccess"
          class="space-y-4">
          <!-- General error -->
          <div
            v-if="error"
            class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
            role="alert">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg
                  class="h-5 w-5 text-red-400"
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
                <p class="text-sm text-red-800 dark:text-red-200">
                  {{ error }}
                </p>
              </div>
            </div>
          </div>

          <!-- Field error (for invalid key) -->
          <div
            v-if="fieldError && fieldError[0] === 'key'"
            class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
            role="alert">
            <p class="text-sm text-red-800 dark:text-red-200">
              {{ $t('web.auth.verify.invalid-key') }}
            </p>
          </div>

          <!-- Help text -->
          <div class="text-center text-sm">
            <p class="text-gray-600 dark:text-gray-400">
              {{ $t('web.auth.verify.check-email') }}
            </p>
          </div>

          <!-- Return to signin link -->
          <div class="text-center">
            <router-link
              to="/signin"
              class="font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
              {{ $t('web.login.button_sign_in') }}
            </router-link>
          </div>
        </div>

        <!-- No key provided -->
        <div
          v-else-if="!verificationKey"
          class="rounded-md bg-yellow-50 p-4 dark:bg-yellow-900/20">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg
                class="h-5 w-5 text-yellow-400"
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 20 20"
                fill="currentColor"
                aria-hidden="true">
                <path
                  fill-rule="evenodd"
                  d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
                  clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <p class="text-sm text-yellow-800 dark:text-yellow-200">
                {{ $t('web.auth.verify.check-email') }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </BaseLayout>
</template>
