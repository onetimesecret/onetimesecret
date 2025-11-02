<!-- AccountChangePasswordForm.vue -->

<script setup lang="ts">
import { usePasswordChange } from '@/composables/usePasswordChange';
import OIcon from '@/components/icons/OIcon.vue';
import { useI18n } from 'vue-i18n';

interface Props {
  apitoken?: string;
}

const { t } = useI18n();
defineProps<Props>();
const emit = defineEmits(['update:password']);

const { formState, isValid, handleSubmit, togglePassword } = usePasswordChange(emit);
</script>

<template>
  <form @submit.prevent="handleSubmit">
    <!-- Visually Hidden Fields -->
    <div class="hidden">
      <label for="username">{{ t('web.account.changePassword.username') }}</label>
      <input type="text"
             id="username"
             autocomplete="username" />
    </div>

    <div class="relative mb-4">
      <label for="currentPassword"
             id="currentPasswordLabel"
             class="block text-sm font-medium text-gray-700 dark:text-gray-300">
        {{ t('web.account.changePassword.currentPassword') }}
      </label>
      <div class="relative">
        <input :type="formState.showPassword.current ? 'text' : 'password'"
               name="currentp"
               id="currentPassword"
               v-model="formState.currentPassword"
               required
               tabindex="0"
               autocomplete="current-password"
               :aria-label="t('web.account.changePassword.currentPassword')"
               aria-labelledby="currentPasswordLabel"
               class="mt-1 block w-full rounded-md border-gray-300 pr-10 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
        <button type="button"
                @click="togglePassword('current')"
                class="absolute inset-y-0 right-0 flex items-center pr-3">
          <OIcon collection="heroicons-solid"
                :name="formState.showPassword.current ? 'eye' : 'eye-off'"
                class="size-5 text-gray-400 dark:text-gray-100"
                aria-hidden="true" />
        </button>
      </div>
    </div>

    <div class="relative mb-4">
      <label for="newPassword"
             id="newPasswordLabel"
             class="block text-sm font-medium text-gray-700 dark:text-gray-300">
        {{ t('web.account.changePassword.newPassword') }}
      </label>
      <div class="relative">
        <input :type="formState.showPassword.new ? 'text' : 'password'"
               name="newpassword"
               id="newPassword"
               v-model="formState.newPassword"
               required
               tabindex="0"
               autocomplete="new-password"
               :aria-label="t('web.account.changePassword.newPassword')"
               aria-labelledby="newPasswordLabel"
               class="mt-1 block w-full rounded-md border-gray-300 pr-10 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
        <button type="button"
                @click="togglePassword('new')"
                class="absolute inset-y-0 right-0 flex items-center pr-3">
          <OIcon collection="heroicons-solid"
                :name="formState.showPassword.new ? 'eye' : 'eye-off'"
                class="size-5 text-gray-400 dark:text-gray-100"
                aria-hidden="true" />
        </button>
      </div>
    </div>

    <div class="relative mb-4">
      <label for="confirmPassword"
             id="confirmPasswordLabel"
             class="block text-sm font-medium text-gray-700 dark:text-gray-300">
        {{ t('web.account.changePassword.confirmPassword') }}
      </label>
      <div class="relative">
        <input :type="formState.showPassword.confirm ? 'text' : 'password'"
               name="password-confirm"
               id="confirmPassword"
               v-model="formState.confirmPassword"
               required
               tabindex="0"
               autocomplete="confirm-password"
               :aria-label="t('web.account.changePassword.newPassword')"
               aria-labelledby="confirmPasswordLabel"
               class="mt-1 block w-full rounded-md border-gray-300 pr-10 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
        <button type="button"
                @click="togglePassword('confirm')"
                class="absolute inset-y-0 right-0 flex items-center pr-3">
          <OIcon collection="heroicons-solid"
                :name="formState.showPassword.confirm ? 'eye' : 'eye-off'"
                class="size-5 text-gray-400 dark:text-gray-100"
                aria-hidden="true" />
        </button>
      </div>
    </div>

    <!-- Notification messages -->
    <div v-if="formState.error" class="mb-4 text-red-500">
      {{ formState.error }}
    </div>
    <div v-if="formState.success" class="mb-4 text-green-500">
      {{ formState.success }}
    </div>

    <button type="submit"
            :disabled="!isValid || formState.isSubmitting"
            class="flex w-full items-center justify-center rounded bg-gray-500 px-4 py-2 text-white hover:bg-gray-600 disabled:opacity-50">
      <i class="fas fa-save mr-2"></i>
      {{ formState.isSubmitting ? t('web.account.changePassword.updating') : t('web.account.changePassword.updatePassword') }}
    </button>
  </form>
</template>
