<script setup lang="ts">
import { useFormSubmission } from '@/composables/useFormSubmission';
import { useCsrfStore } from '@/stores/csrfStore';
import { Icon } from '@iconify/vue';
import { ref, reactive } from 'vue';

const csrfStore = useCsrfStore();

const currentPassword = ref('');
const newPassword = ref('');
const confirmPassword = ref('');

const showPassword = reactive({
  current: false,
  new: false,
  confirm: false
});


interface Props {
  apitoken?: string;
}

defineProps<Props>();
const emit = defineEmits(['update:password']);


const {
  isSubmitting: isUpdatingPassword,
  error: passwordError,
  success: passwordSuccess,
  submitForm: updatePassword
} = useFormSubmission({
  url: '/api/v2/account/change-password',
  successMessage: 'Password updated successfully.',
  onSuccess() {
    emit('update:password');
  },
});

const togglePassword = (field: 'current' | 'new' | 'confirm') => {
  showPassword[field] = !showPassword[field];
};
</script>

<template>
  <form @submit.prevent="updatePassword">
    <input
      type="hidden"
      name="shrimp"
      :value="csrfStore.shrimp"
    />

    <!-- Visually Hidden Fields -->
    <div class="hidden">
      <label for="username">Username</label>
      <input
        type="text"
        id="username"
        autocomplete="username"
      />
    </div>

    <div class="relative mb-4">
      <label
        for="currentPassword"
        id="currentPasswordLabel"
        class="block text-sm font-medium text-gray-700 dark:text-gray-300">Current Password</label>

      <div class="relative">
        <input
          :type="showPassword.current ? 'text' : 'password'"
          name="currentp"
          id="currentPassword"
          v-model="currentPassword"
          required
          tabindex="1"
          autocomplete="current-password"
          aria-label="Current Password"
          aria-labelledby="currentPasswordLabel"
          class="mt-1 block w-full rounded-md border-gray-300 pr-10 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
        />
        <button
          type="button"
          @click="togglePassword('current')"
          class="absolute inset-y-0 right-0 flex items-center pr-3">
          <Icon
            :icon="showPassword.current ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
            class="size-5 text-gray-400 dark:text-gray-100"
            aria-hidden="true"
          />
        </button>
      </div>
    </div>
    <div class="relative mb-4">
      <label
        for="newPassword"
        id="newPasswordLabel"
        class="block text-sm font-medium text-gray-700 dark:text-gray-300">New Password</label>

      <div class="relative">
        <input
          :type="showPassword.new ? 'text' : 'password'"
          name="newp"
          id="newPassword"
          v-model="newPassword"
          required
          tabindex="2"
          autocomplete="new-password"
          aria-label="New Password"
          aria-labelledby="newPasswordLabel"
          class="mt-1 block w-full rounded-md border-gray-300 pr-10 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
        />
        <button
          type="button"
          @click="togglePassword('new')"
          class="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-400 hover:text-gray-600 dark:text-gray-300 dark:hover:text-gray-100">
          <Icon
            :icon="showPassword.new ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
            class="size-5 text-gray-400 dark:text-gray-100"
            aria-hidden="true"
          />
        </button>
      </div>
    </div>
    <div class="relative mb-4">
      <label
        for="confirmPassword"
        id="confirmPasswordlabel"
        class="block text-sm font-medium text-gray-700 dark:text-gray-300">Confirm</label>

      <div class="relative">
        <input
          :type="showPassword.confirm ? 'text' : 'password'"
          name="newp2"
          id="confirmPassword"
          v-model="confirmPassword"
          required
          tabindex="3"
          autocomplete="confirm-password"
          aria-label="New Password"
          aria-labelledby="confirmPasswordlabel"
          class="mt-1 block w-full rounded-md border-gray-300 pr-10 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
        />
        <button
          type="button"
          @click="togglePassword('confirm')"
          class="absolute inset-y-0 right-0 flex items-center pr-3">
          <Icon
            :icon="showPassword.confirm ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
            class="size-5 text-gray-400 dark:text-gray-100"
            aria-hidden="true"
          />
        </button>
      </div>
    </div>

    <div
      v-if="passwordError"
      class="mb-4 text-red-500">
      {{ passwordError }}
    </div>
    <div
      v-if="passwordSuccess"
      class="mb-4 text-green-500">
      {{ passwordSuccess }}
    </div>

    <button
      type="submit"
      class="flex w-full items-center justify-center rounded bg-gray-500 px-4 py-2 text-white hover:bg-gray-600">
      <i class="fas fa-save mr-2"></i> {{ isUpdatingPassword ? 'Updating...' : 'Update Password' }}
    </button>
  </form>
</template>
