<script setup lang="ts">
import { useFormSubmission } from '@/composables/useFormSubmission';
import { Customer } from '@/schemas/models';
import { useCsrfStore } from '@/stores/csrfStore';
import { ref } from 'vue';

const csrfStore = useCsrfStore();

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
  successMessage: 'Account deleted successfully.',
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
  <p class="dark:text-gray-300 mb-4">Please be advised:</p>
  <ul class="dark:text-gray-300 mb-4 list-disc list-inside">
    <li><span class="font-bold">Secrets will remain active until they expire.</span></li>
    <li>Any secrets you wish to remove, <span
         class="underline">burn them before continuing</span>.</li>
    <li>Deleting your account is <span class="italic">permanent and non-reversible.</span></li>
  </ul>
  <button @click="openDeleteModal"
          class="hover:bg-red-700 flex items-center justify-center w-full px-4 py-2 font-bold text-white bg-red-600 rounded">
    <i class="fas fa-trash-alt mr-2"></i> Permanently Delete Account
  </button>
  <p class="dark:text-gray-400 mt-2 text-sm text-gray-500">Deleting {{ cust?.custid }}</p>

  <!-- Delete Account Confirmation Modal -->
  <div v-if="showDeleteModal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
    <form @submit.prevent="submitDeleteAccount"
          class="w-full max-w-md">
      <input type="hidden"
              name="shrimp"
              :value="csrfStore.shrimp" />

      <div class="dark:bg-gray-800 p-6 bg-white rounded-lg shadow-lg">
        <h3 class="dark:text-white mb-4 text-xl font-bold text-gray-900">Confirm Account Deletion</h3>
        <p class="dark:text-gray-300 mb-4 text-gray-700">Are you sure you want to permanently delete your account?
          This action cannot be undone.</p>

        <input type="hidden"
                name="tabindex"
                value="destroy" />

        <div class="mb-4">
          <input v-model="deletePassword"
                  name="confirmation"
                  type="password"
                  class="focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white w-full px-3 py-2 border border-gray-300 rounded-md"
                  autocomplete="confirmation"
                  placeholder="Confirm with your password" />
        </div>

        <p v-if="deleteError"
            class="mb-4 text-red-500">{{ deleteError }}</p>
        <p v-if="deleteSuccess"
            class="mb-4 text-green-500">{{ deleteSuccess }}</p>

        <div class="flex justify-end space-x-4">
          <button @click="closeDeleteModal"
                  type="button"
                  class="hover:bg-gray-300 focus:outline-none focus:ring-2 focus:ring-gray-400 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600 px-4 py-2 text-gray-800 bg-gray-200 rounded-md">
            Cancel
          </button>
          <button type="submit"
                  :disabled="!deletePassword || isDeleting"
                  class="hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 dark:bg-red-700 dark:hover:bg-red-800 disabled:opacity-50 disabled:cursor-not-allowed flex items-center px-4 py-2 text-white bg-red-600 rounded-md">
            <svg v-if="isDeleting"
                  class="animate-spin w-5 h-5 mr-3 -ml-1 text-white"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24">
              <circle class="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      stroke-width="4"></circle>
              <path class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z">
              </path>
            </svg>
            <svg v-else
                  xmlns="http://www.w3.org/2000/svg"
                  class="w-5 h-5 mr-2"
                  width="20"
                  height="20"
                  viewBox="0 0 20 20"
                  fill="currentColor">
              <path fill-rule="evenodd"
                    d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z"
                    clip-rule="evenodd" />
            </svg>
            {{ isDeleting ? 'Deleting...' : 'Delete Account' }}
          </button>
        </div>
      </div>
    </form>
  </div>
</template>
