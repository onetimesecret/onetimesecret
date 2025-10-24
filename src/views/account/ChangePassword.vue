<!-- src/views/account/ChangePassword.vue -->
<script setup lang="ts">
import { ref, computed } from 'vue';
import { useAuth } from '@/composables/useAuth';

const { changePassword, isLoading, error, fieldError, clearErrors } = useAuth();

const currentPassword = ref('');
const newPassword = ref('');
const confirmPassword = ref('');
const showCurrentPassword = ref(false);
const showNewPassword = ref(false);
const showConfirmPassword = ref(false);

const toggleCurrentPasswordVisibility = () => {
  showCurrentPassword.value = !showCurrentPassword.value;
};

const toggleNewPasswordVisibility = () => {
  showNewPassword.value = !showNewPassword.value;
};

const toggleConfirmPasswordVisibility = () => {
  showConfirmPassword.value = !showConfirmPassword.value;
};

// Client-side validation
const passwordsMatch = computed(() => {
  if (!newPassword.value || !confirmPassword.value) return true;
  return newPassword.value === confirmPassword.value;
});

const passwordMinLength = computed(() => {
  if (!newPassword.value) return true;
  return newPassword.value.length >= 8;
});

const canSubmit = computed(() => (
    currentPassword.value.length > 0 &&
    newPassword.value.length >= 8 &&
    confirmPassword.value.length >= 8 &&
    passwordsMatch.value &&
    !isLoading.value
  ));

const handleSubmit = async () => {
  clearErrors();

  if (!canSubmit.value) return;

  const success = await changePassword(
    currentPassword.value,
    newPassword.value,
    confirmPassword.value
  );

  if (success) {
    // Clear form on success
    currentPassword.value = '';
    newPassword.value = '';
    confirmPassword.value = '';
  }
};
</script>

<template>
  <div class="mx-auto max-w-2xl">
    <div class="bg-white shadow dark:bg-gray-800 sm:rounded-lg">
      <div class="px-4 py-5 sm:p-6">
        <h3 class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
          {{ $t('web.auth.change-password.title') }}
        </h3>
        <div class="mt-2 max-w-xl text-sm text-gray-500 dark:text-gray-400">
          <p>{{ $t('web.COMMON.field_password') }} ({{ $t('web.COMMON.minimum_8_characters') }})</p>
        </div>

        <form
          @submit.prevent="handleSubmit"
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

          <!-- Current password -->
          <div>
            <label
              for="current-password"
              class="block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ $t('web.auth.change-password.current-password') }}
            </label>
            <div class="relative mt-1">
              <input
                id="current-password"
                :type="showCurrentPassword ? 'text' : 'password'"
                v-model="currentPassword"
                autocomplete="current-password"
                required
                :disabled="isLoading"
                :aria-invalid="fieldError?.[0] === 'password'"
                :aria-describedby="fieldError?.[0] === 'password' ? 'current-password-error' : undefined"
                class="block w-full rounded-md border-gray-300 pr-10 shadow-sm
                       focus:border-brand-500 focus:ring-brand-500
                       disabled:opacity-50 disabled:cursor-not-allowed
                       dark:border-gray-600 dark:bg-gray-700 dark:text-white
                       sm:text-sm" />
              <button
                type="button"
                @click="toggleCurrentPasswordVisibility"
                :disabled="isLoading"
                class="absolute inset-y-0 right-0 flex items-center pr-3 disabled:opacity-50"
                :aria-label="showCurrentPassword ? $t('web.COMMON.hide-password') : $t('web.COMMON.show-password')">
                <svg
                  class="h-5 w-5 text-gray-400"
                  :class="{ 'hidden': showCurrentPassword, 'block': !showCurrentPassword }"
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 576 512"
                  aria-hidden="true">
                  <path
                    fill="currentColor"
                    d="M572.52 241.4C518.29 135.59 410.93 64 288 64S57.68 135.64 3.48 241.41a32.35 32.35 0 0 0 0 29.19C57.71 376.41 165.07 448 288 448s230.32-71.64 284.52-177.41a32.35 32.35 0 0 0 0-29.19zM288 400a144 144 0 1 1 144-144 143.93 143.93 0 0 1-144 144zm0-240a95.31 95.31 0 0 0-25.31 3.79 47.85 47.85 0 0 1-66.9 66.9A95.78 95.78 0 1 0 288 160z" />
                </svg>
                <svg
                  class="h-5 w-5 text-gray-400"
                  :class="{ 'block': showCurrentPassword, 'hidden': !showCurrentPassword }"
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
              id="current-password-error"
              role="alert"
              class="mt-2 text-sm text-red-600 dark:text-red-400">
              {{ fieldError[1] }}
            </p>
          </div>

          <!-- New password -->
          <div>
            <label
              for="new-password"
              class="block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ $t('web.auth.change-password.new-password') }}
            </label>
            <div class="relative mt-1">
              <input
                id="new-password"
                :type="showNewPassword ? 'text' : 'password'"
                v-model="newPassword"
                autocomplete="new-password"
                required
                :disabled="isLoading"
                :aria-invalid="fieldError?.[0] === 'newp' || !passwordMinLength"
                :aria-describedby="fieldError?.[0] === 'newp' ? 'new-password-error' : undefined"
                class="block w-full rounded-md border-gray-300 pr-10 shadow-sm
                       focus:border-brand-500 focus:ring-brand-500
                       disabled:opacity-50 disabled:cursor-not-allowed
                       dark:border-gray-600 dark:bg-gray-700 dark:text-white
                       sm:text-sm" />
              <button
                type="button"
                @click="toggleNewPasswordVisibility"
                :disabled="isLoading"
                class="absolute inset-y-0 right-0 flex items-center pr-3 disabled:opacity-50"
                :aria-label="showNewPassword ? $t('web.COMMON.hide-password') : $t('web.COMMON.show-password')">
                <svg
                  class="h-5 w-5 text-gray-400"
                  :class="{ 'hidden': showNewPassword, 'block': !showNewPassword }"
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 576 512"
                  aria-hidden="true">
                  <path
                    fill="currentColor"
                    d="M572.52 241.4C518.29 135.59 410.93 64 288 64S57.68 135.64 3.48 241.41a32.35 32.35 0 0 0 0 29.19C57.71 376.41 165.07 448 288 448s230.32-71.64 284.52-177.41a32.35 32.35 0 0 0 0-29.19zM288 400a144 144 0 1 1 144-144 143.93 143.93 0 0 1-144 144zm0-240a95.31 95.31 0 0 0-25.31 3.79 47.85 47.85 0 0 1-66.9 66.9A95.78 95.78 0 1 0 288 160z" />
                </svg>
                <svg
                  class="h-5 w-5 text-gray-400"
                  :class="{ 'block': showNewPassword, 'hidden': !showNewPassword }"
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
              v-if="fieldError?.[0] === 'newp'"
              id="new-password-error"
              role="alert"
              class="mt-2 text-sm text-red-600 dark:text-red-400">
              {{ fieldError[1] }}
            </p>
            <p
              v-else-if="newPassword && !passwordMinLength"
              class="mt-2 text-sm text-red-600 dark:text-red-400">
              {{ $t('web.COMMON.minimum_8_characters') }}
            </p>
          </div>

          <!-- Confirm new password -->
          <div>
            <label
              for="confirm-password"
              class="block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ $t('web.auth.change-password.confirm-password') }}
            </label>
            <div class="relative mt-1">
              <input
                id="confirm-password"
                :type="showConfirmPassword ? 'text' : 'password'"
                v-model="confirmPassword"
                autocomplete="new-password"
                required
                :disabled="isLoading"
                :aria-invalid="fieldError?.[0] === 'newp2' || !passwordsMatch"
                :aria-describedby="fieldError?.[0] === 'newp2' ? 'confirm-password-error' : undefined"
                class="block w-full rounded-md border-gray-300 pr-10 shadow-sm
                       focus:border-brand-500 focus:ring-brand-500
                       disabled:opacity-50 disabled:cursor-not-allowed
                       dark:border-gray-600 dark:bg-gray-700 dark:text-white
                       sm:text-sm" />
              <button
                type="button"
                @click="toggleConfirmPasswordVisibility"
                :disabled="isLoading"
                class="absolute inset-y-0 right-0 flex items-center pr-3 disabled:opacity-50"
                :aria-label="showConfirmPassword ? $t('web.COMMON.hide-password') : $t('web.COMMON.show-password')">
                <svg
                  class="h-5 w-5 text-gray-400"
                  :class="{ 'hidden': showConfirmPassword, 'block': !showConfirmPassword }"
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 576 512"
                  aria-hidden="true">
                  <path
                    fill="currentColor"
                    d="M572.52 241.4C518.29 135.59 410.93 64 288 64S57.68 135.64 3.48 241.41a32.35 32.35 0 0 0 0 29.19C57.71 376.41 165.07 448 288 448s230.32-71.64 284.52-177.41a32.35 32.35 0 0 0 0-29.19zM288 400a144 144 0 1 1 144-144 143.93 143.93 0 0 1-144 144zm0-240a95.31 95.31 0 0 0-25.31 3.79 47.85 47.85 0 0 1-66.9 66.9A95.78 95.78 0 1 0 288 160z" />
                </svg>
                <svg
                  class="h-5 w-5 text-gray-400"
                  :class="{ 'block': showConfirmPassword, 'hidden': !showConfirmPassword }"
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
              v-if="fieldError?.[0] === 'newp2'"
              id="confirm-password-error"
              role="alert"
              class="mt-2 text-sm text-red-600 dark:text-red-400">
              {{ fieldError[1] }}
            </p>
            <p
              v-else-if="confirmPassword && !passwordsMatch"
              class="mt-2 text-sm text-red-600 dark:text-red-400">
              {{ $t('web.COMMON.passwords_do_not_match') }}
            </p>
          </div>

          <!-- Submit button -->
          <div class="flex justify-end">
            <button
              type="submit"
              :disabled="!canSubmit"
              class="inline-flex justify-center rounded-md border border-transparent
                     bg-brand-600 px-4 py-2 text-sm font-medium text-white shadow-sm
                     hover:bg-brand-700 focus:outline-none focus:ring-2
                     focus:ring-brand-500 focus:ring-offset-2
                     disabled:opacity-50 disabled:cursor-not-allowed
                     dark:bg-brand-600 dark:hover:bg-brand-700">
              <span v-if="isLoading">{{ $t('web.COMMON.processing') }}</span>
              <span v-else>{{ $t('web.auth.change-password.title') }}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
