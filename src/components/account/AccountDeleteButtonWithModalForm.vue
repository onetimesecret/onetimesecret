<script setup lang="ts">
import { useFormSubmission } from '@/composables/useFormSubmission';
import { Customer } from '@/schemas/models';
import { useCsrfStore } from '@/stores/csrfStore';
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const csrfStore = useCsrfStore();
const { t } = useI18n();

interface Props {
  apitoken?: string;
  cust: Customer;
}

defineProps<Props>();
const emit = defineEmits(['delete:account']);

const showDeleteModal = ref(false);
const deletePassword = ref('');

const {
  isSubmitting: isDeleting,
  error: deleteError,
  success: deleteSuccess,
  submitForm: submitDeleteAccount
} = useFormSubmission({
  url: '/api/v2/account/destroy',
  successMessage: t('account-deleted-successfully'),
  onSuccess: () => {
    emit('delete:account');
    showDeleteModal.value = false;
    window.location.href = '/';
  },
});

const openDeleteModal = () => {
  showDeleteModal.value = true;
};

const closeDeleteModal = () => {
  showDeleteModal.value = false;
  deletePassword.value = '';
};
</script>

<template>
  <p class="mb-4 dark:text-gray-300">
    {{ $t('please-be-advised') }}
  </p>
  <ul class="mb-4 list-inside list-disc dark:text-gray-300">
    <li><span class="font-bold">{{ $t('secrets-will-remain-active-until-they-expire') }}</span></li>
    <li>
      {{ $t('any-secrets-you-wish-to-remove') }} <span
        class="underline">{{ $t('burn-them-before-continuing') }}</span>.
    </li>
    <li>{{ $t('deleting-your-account-is') }} <span class="italic">{{ $t('permanent-and-non-reversible') }}</span></li>
  </ul>
  <button
    @click="openDeleteModal"
    class="flex w-full items-center justify-center rounded bg-red-600 px-4 py-2 font-bold text-white hover:bg-red-700">
    <i class="fas fa-trash-alt mr-2"></i> {{ $t('permanently-delete-account') }}
  </button>
  <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
    {{ $t('deleting-cust-custid', [cust?.extid]) }}
  </p>

  <!-- Delete Account Confirmation Modal -->
  <div
    v-if="showDeleteModal"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
    <form
      @submit.prevent="submitDeleteAccount"
      class="w-full max-w-md">
      <input
        type="hidden"
        name="shrimp"
        :value="csrfStore.shrimp"
      />

      <div class="rounded-lg bg-white p-6 shadow-lg dark:bg-gray-800">
        <h3 class="mb-4 text-xl font-bold text-gray-900 dark:text-white">
          {{ $t('confirm-account-deletion') }}
        </h3>
        <p class="mb-4 text-gray-700 dark:text-gray-300">
          {{ $t('are-you-sure-you-want-to-permanently-delete-your') }}
        </p>

        <input
          type="hidden"
          name="tabindex"
          value="destroy"
        />

        <div class="mb-4">
          <input
            v-model="deletePassword"
            name="confirmation"
            type="password"
            class="w-full rounded-md border border-gray-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
            autocomplete="confirmation"
            placeholder="$t('confirm-with-your-password')"
          />
        </div>

        <p
          v-if="deleteError"
          class="mb-4 text-red-500">
          {{ deleteError }}
        </p>
        <p
          v-if="deleteSuccess"
          class="mb-4 text-green-500">
          {{ deleteSuccess }}
        </p>

        <div class="flex justify-end space-x-4">
          <button
            @click="closeDeleteModal"
            type="button"
            class="rounded-md bg-gray-200 px-4 py-2 text-gray-800 hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-gray-400 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600">
            {{ $t('web.COMMON.word_cancel') }}
          </button>
          <button
            type="submit"
            :disabled="!deletePassword || isDeleting"
            class="flex items-center rounded-md bg-red-600 px-4 py-2 text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-red-700 dark:hover:bg-red-800">
            <svg
              v-if="isDeleting"
              class="-ml-1 mr-3 size-5 animate-spin text-white"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24">
              <circle
                class="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                stroke-width="4"
              />
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              />
            </svg>
            <svg
              v-else
              xmlns="http://www.w3.org/2000/svg"
              class="mr-2 size-5"
              width="20"
              height="20"
              viewBox="0 0 20 20"
              fill="currentColor">
              <path
                fill-rule="evenodd"
                d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z"
                clip-rule="evenodd"
              />
            </svg>
            {{ isDeleting ? 'Deleting...' : 'Delete Account' }}
          </button>
        </div>
      </div>
    </form>
  </div>
</template>
