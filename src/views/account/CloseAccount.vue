<!-- src/views/account/CloseAccount.vue -->
<script setup lang="ts">
  import { ref, computed } from 'vue';
  import { useAuth } from '@/composables/useAuth';

  const { closeAccount, isLoading, error, fieldError, clearErrors } = useAuth();

  const password = ref('');
  const showPassword = ref(false);
  const confirmationChecked = ref(false);
  const showConfirmation = ref(false);

  const togglePasswordVisibility = () => {
    showPassword.value = !showPassword.value;
  };

  const canSubmit = computed(
    () => password.value.length > 0 && confirmationChecked.value && !isLoading.value
  );

  const handleInitialSubmit = () => {
    clearErrors();
    showConfirmation.value = true;
  };

  const handleFinalSubmit = async () => {
    clearErrors();

    if (!canSubmit.value) return;

    await closeAccount(password.value);
    // Navigation handled by useAuth composable (logout + redirect to /)
  };

  const handleCancel = () => {
    password.value = '';
    showConfirmation.value = false;
    confirmationChecked.value = false;
    clearErrors();
  };
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <!-- Warning banner -->
    <div class="mb-6 rounded-md bg-red-50 p-4 dark:bg-red-900/20">
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
              d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
              clip-rule="evenodd" />
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-red-800 dark:text-red-200">
            {{ $t('web.COMMON.caution_zone') }}
          </h3>
          <div class="mt-2 text-sm text-red-700 dark:text-red-300">
            <p>{{ $t('web.auth.close-account.warning') }}</p>
          </div>
        </div>
      </div>
    </div>

    <div class="bg-white shadow dark:bg-gray-800 sm:rounded-lg">
      <div class="px-4 py-5 sm:p-6">
        <h3 class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
          {{ $t('web.auth.close-account.title') }}
        </h3>

        <!-- Initial form (before confirmation) -->
        <form
          v-if="!showConfirmation"
          @submit.prevent="handleInitialSubmit"
          class="mt-5 space-y-4">
          <!-- General error -->
          <div
            v-if="error && !fieldError"
            class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
            role="alert">
            <p class="text-sm text-red-800 dark:text-red-200">
              {{ error }}
            </p>
          </div>

          <!-- Password confirmation -->
          <div>
            <label
              for="password"
              class="block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ $t('web.auth.close-account.password') }}
            </label>
            <div class="relative mt-1">
              <input
                id="password"
                :type="showPassword ? 'text' : 'password'"
                v-model="password"
                autocomplete="current-password"
                required
                :disabled="isLoading"
                :aria-invalid="fieldError?.[0] === 'password'"
                :aria-describedby="fieldError?.[0] === 'password' ? 'password-error' : undefined"
                class="block w-full rounded-md border-gray-300 pr-10 shadow-sm focus:border-brand-500 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white sm:text-sm" />
              <button
                type="button"
                @click="togglePasswordVisibility"
                :disabled="isLoading"
                class="absolute inset-y-0 right-0 flex items-center pr-3 disabled:opacity-50"
                :aria-label="
                  showPassword ? $t('web.COMMON.hide-password') : $t('web.COMMON.show-password')
                ">
                <svg
                  class="h-5 w-5 text-gray-400"
                  :class="{ hidden: showPassword, block: !showPassword }"
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 576 512"
                  aria-hidden="true">
                  <path
                    fill="currentColor"
                    d="M572.52 241.4C518.29 135.59 410.93 64 288 64S57.68 135.64 3.48 241.41a32.35 32.35 0 0 0 0 29.19C57.71 376.41 165.07 448 288 448s230.32-71.64 284.52-177.41a32.35 32.35 0 0 0 0-29.19zM288 400a144 144 0 1 1 144-144 143.93 143.93 0 0 1-144 144zm0-240a95.31 95.31 0 0 0-25.31 3.79 47.85 47.85 0 0 1-66.9 66.9A95.78 95.78 0 1 0 288 160z" />
                </svg>
                <svg
                  class="h-5 w-5 text-gray-400"
                  :class="{ block: showPassword, hidden: !showPassword }"
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 640 512"
                  aria-hidden="true">
                  <path
                    fill="currentColor"
                    d="M320 400c-75.85 0-137.25-58.71-142.9-133.11L72.2 185.82c-13.79 17.3-26.48 35.59-36.72 55.59a32.35 32.35 0 0 0 0 29.19C89.71 376.41 197.07 448 320 448c26.91 0 52.87-4 77.89-10.46L346 397.39a144.13 144.13 0 0 1-26 2.61zm313.82 58.1l-110.55-85.44a331.25 331.25 0 0 0 81.25-102.07 32.35 32.35 0 0 0 0-29.19C550.29 135.59 442.93 64 320 64a308.15 308.15 0 0 0-147.32 37.7L45.46 3.37A16 16 0 0 0 23 6.18L3.37 31.45A16 16 0 0 0 6.18 53.9l588.36 454.73a16 16 0 0 0 22.46-2.81l19.64-25.27a16 16 0 0 0-2.82-22.45zm-183.72-142l-39.3-30.38A94.75 94.75 0 0 0 416 256a94.76 94.76 0 0 0-121.31-92.21A47.65 47.65 0 0 1 304 192a46.64 46.64 0 0 1-1.54 10l-73.61-56.89A142.31 142.31 0 0 1 320 112a143.92 143.92 0 0 1 144 144c0 21.63-5.29 41.79-13.9 60.11z" />
                </svg>
              </button>
            </div>
            <p
              v-if="fieldError?.[0] === 'password'"
              id="password-error"
              role="alert"
              class="mt-2 text-sm text-red-600 dark:text-red-400">
              {{ fieldError[1] }}
            </p>
          </div>

          <!-- Confirmation checkbox -->
          <div class="flex items-start">
            <div class="flex h-5 items-center">
              <input
                id="confirm"
                type="checkbox"
                v-model="confirmationChecked"
                :disabled="isLoading"
                class="h-4 w-4 rounded border-gray-300 text-red-600 focus:ring-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:ring-offset-gray-800 dark:focus:ring-red-500" />
            </div>
            <div class="ml-3 text-sm">
              <label
                for="confirm"
                class="font-medium text-gray-700 dark:text-gray-300">
                {{ $t('web.auth.close-account.confirm') }}
              </label>
            </div>
          </div>

          <!-- Action buttons -->
          <div class="flex justify-end space-x-3">
            <button
              type="button"
              @click="$router.push('/account/settings')"
              :disabled="isLoading"
              class="inline-flex justify-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600">
              {{ $t('web.auth.close-account.cancel') }}
            </button>
            <button
              type="submit"
              :disabled="!password || !confirmationChecked || isLoading"
              class="inline-flex justify-center rounded-md border border-transparent bg-red-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
              {{ $t('web.COMMON.continue') }}
            </button>
          </div>
        </form>

        <!-- Final confirmation (after checkbox) -->
        <div
          v-else
          class="mt-5 space-y-4">
          <div class="rounded-md bg-red-50 p-4 dark:bg-red-900/20">
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
                <h3 class="text-sm font-medium text-red-800 dark:text-red-200">
                  {{ $t('web.COMMON.are_you_sure') }}
                </h3>
                <div class="mt-2 text-sm text-red-700 dark:text-red-300">
                  <p>{{ $t('web.auth.close-account.warning') }}</p>
                </div>
              </div>
            </div>
          </div>

          <!-- General error (on final submit) -->
          <div
            v-if="error && !fieldError"
            class="rounded-md bg-red-50 p-4 dark:bg-red-900/20"
            role="alert">
            <p class="text-sm text-red-800 dark:text-red-200">
              {{ error }}
            </p>
          </div>

          <!-- Final action buttons -->
          <div class="flex justify-end space-x-3">
            <button
              type="button"
              @click="handleCancel"
              :disabled="isLoading"
              class="inline-flex justify-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600">
              {{ $t('web.auth.close-account.cancel') }}
            </button>
            <button
              type="button"
              @click="handleFinalSubmit"
              :disabled="!canSubmit"
              class="inline-flex justify-center rounded-md border border-transparent bg-red-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50">
              <span v-if="isLoading">{{ $t('web.COMMON.processing') }}</span>
              <span v-else>{{ $t('web.auth.close-account.button') }}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
