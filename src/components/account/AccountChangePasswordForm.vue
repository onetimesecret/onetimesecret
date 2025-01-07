<!-- AccountChangePasswordForm.vue -->
<script setup lang="ts">
import { usePasswordChange } from '@/composables/usePasswordChange';
import { Icon } from '@iconify/vue';

interface Props {
  apitoken?: string;
}

defineProps<Props>();
const emit = defineEmits(['update:password']);

const { formState, isValid, handleSubmit, togglePassword } = usePasswordChange(emit);
</script>

<template>
  <form @submit.prevent="handleSubmit">
    <!-- Visually Hidden Fields -->
    <div class="hidden">
      <label for="username">Username</label>
      <input type="text"
             id="username"
             autocomplete="username" />
    </div>

    <div class="relative mb-4">
      <label for="currentPassword"
             id="currentPasswordLabel"
             class="block text-sm font-medium text-gray-700 dark:text-gray-300">Current Password</label>

      <div class="relative">
        <input :type="formState.showPassword.current ? 'text' : 'password'"
               name="currentp"
               id="currentPassword"
               v-model="formState.currentPassword"
               required
               tabindex="1"
               autocomplete="current-password"
               aria-label="Current Password"
               aria-labelledby="currentPasswordLabel"
               class="mt-1 block w-full rounded-md border-gray-300 pr-10 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
        <button type="button"
                @click="togglePassword('current')"
                class="absolute inset-y-0 right-0 flex items-center pr-3">
          <Icon :icon="formState.showPassword.current ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
                class="size-5 text-gray-400 dark:text-gray-100"
                aria-hidden="true" />
        </button>
      </div>
    </div>
    <div class="relative mb-4">
      <label for="newPassword"
             id="newPasswordLabel"
             class="block text-sm font-medium text-gray-700 dark:text-gray-300">New Password</label>

      <div class="relative">
        <input :type="formState.showPassword.new ? 'text' : 'password'"
               name="newp"
               id="newPassword"
               v-model="formState.newPassword"
               required
               tabindex="2"
               autocomplete="new-password"
               aria-label="New Password"
               aria-labelledby="newPasswordLabel"
               class="mt-1 block w-full rounded-md border-gray-300 pr-10 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
        <button type="button"
                @click="togglePassword('new')"
                class="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-400 hover:text-gray-600 dark:text-gray-300 dark:hover:text-gray-100">
          <Icon :icon="formState.showPassword.new ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
                class="size-5 text-gray-400 dark:text-gray-100"
                aria-hidden="true" />
        </button>
      </div>
    </div>
    <div class="relative mb-4">
      <label for="confirmPassword"
             id="confirmPasswordlabel"
             class="block text-sm font-medium text-gray-700 dark:text-gray-300">Confirm</label>

      <div class="relative">
        <input :type="formState.showPassword.confirm ? 'text' : 'password'"
               name="newp2"
               id="confirmPassword"
               v-model="formState.confirmPassword"
               required
               tabindex="3"
               autocomplete="confirm-password"
               aria-label="New Password"
               aria-labelledby="confirmPasswordlabel"
               class="mt-1 block w-full rounded-md border-gray-300 pr-10 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
        <button type="button"
                @click="togglePassword('confirm')"
                class="absolute inset-y-0 right-0 flex items-center pr-3">
          <Icon :icon="formState.showPassword.confirm ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
                class="size-5 text-gray-400 dark:text-gray-100"
                aria-hidden="true" />
        </button>
      </div>
    </div>

    <!-- Similar updates for new password and confirm password fields -->

    <div v-if="formState.error"
         class="mb-4 text-red-500">
      {{ formState.error }}
    </div>
    <div v-if="formState.success"
         class="mb-4 text-green-500">
      {{ formState.success }}
    </div>

    <button type="submit"
            :disabled="!isValid || formState.isSubmitting"
            class="flex w-full items-center justify-center rounded bg-gray-500 px-4 py-2 text-white hover:bg-gray-600 disabled:opacity-50">
      <i class="fas fa-save mr-2"></i>
      {{ formState.isSubmitting ? 'Updating...' : 'Update Password' }}
    </button>
  </form>
</template>
