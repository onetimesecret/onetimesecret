<template>
  <div class="max-w-2xl mx-auto p-4">
    <h1 class="text-3xl font-bold mb-6 dark:text-white">Your Account</h1>
    <p class="text-lg mb-4 dark:text-gray-300">Account type: {{ accountType }}</p>

    <div class="bg-white dark:bg-gray-800 shadow rounded-lg p-6 mb-6">
      <h2 class="text-xl font-semibold mb-4 dark:text-white flex items-center">
        <i class="fas fa-lock mr-2"></i> Update Password
      </h2>
      <div class="pl-3"> <!-- Added padding-left to align with the title text -->
        <form @submit.prevent="updatePassword">

          <!-- Visually Hidden Fields -->
          <div class="hidden">
            <input type="hidden" name="shrimp" :value="shrimp" />
            <label for="username">Username</label>
            <input type="text" id="username" autocomplete="username" />
          </div>

          <div class="mb-4 relative">
            <label for="currentPassword" class="block text-sm font-medium text-gray-700 dark:text-gray-300">Current Password</label>

            <div class="relative">
              <input :type="showPassword.current ? 'text' : 'password'"
                    name="currentp"
                    id="currentPassword" v-model="currentPassword" required autocomplete="current-password"
                    class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:bg-gray-700 dark:text-white pr-10">
              <button type="button" @click="togglePassword('current')" class="absolute inset-y-0 right-0 pr-3 flex items-center">
                <Icon :icon="showPassword.current ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
                      class="h-5 w-5 text-gray-400 dark:text-gray-100"
                      aria-hidden="true" />
              </button>
            </div>

          </div>
          <div class="mb-4 relative">
            <label for="newPassword" class="block text-sm font-medium text-gray-700 dark:text-gray-300">New Password</label>

            <div class="relative">
              <input :type="showPassword.new ? 'text' : 'password'"
                     name="newp"
                     id="newPassword" v-model="newPassword" required autocomplete="new-password"
                     class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:bg-gray-700 dark:text-white pr-10">
              <button type="button" @click="togglePassword('new')"
                      class="absolute inset-y-0 right-0 pr-3 flex items-center text-gray-400 hover:text-gray-600 dark:text-gray-300 dark:hover:text-gray-100">
                <Icon :icon="showPassword.new ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
                      class="h-5 w-5 text-gray-400 dark:text-gray-100"
                      aria-hidden="true" />
              </button>
            </div>

          </div>
          <div class="mb-4 relative">
            <label for="confirmPassword" class="block text-sm font-medium text-gray-700 dark:text-gray-300">Confirm</label>

            <div class="relative">
              <input :type="showPassword.confirm ? 'text' : 'password'"
                     name="newp2"
                     id="confirmPassword" v-model="confirmPassword" required autocomplete="confirm-password"
                     class="mt-1 block w-full rounded-md border-gray-300 dark:border-gray-600 shadow-sm focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:bg-gray-700 dark:text-white pr-10">
              <button type="button" @click="togglePassword('confirm')" class="absolute inset-y-0 right-0 pr-3 flex items-center">
                <Icon :icon="showPassword.confirm ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
                      class="h-5 w-5 text-gray-400 dark:text-gray-100"
                      aria-hidden="true" />
              </button>
            </div>

          </div>
          <div v-if="updateError" class="text-red-500 mb-4">{{ updateError }}</div>
          <div v-if="successMessage" class="text-green-500 mb-4">{{ successMessage }}</div>

          <button type="submit" class="w-full bg-gray-500 hover:bg-gray-600 text-white py-2 px-4 rounded flex items-center justify-center">
            <i class="fas fa-save mr-2"></i> Update Password
          </button>
        </form>
      </div>
    </div>

    <div class="bg-white dark:bg-gray-800 shadow rounded-lg p-6">
      <h2 class="text-xl font-semibold mb-4 dark:text-white flex items-center">
        <i class="fas fa-exclamation-triangle text-red-500 mr-2"></i>
        <span class="flex-1">Delete Account</span>
      </h2>
      <div class="pl-3"> <!-- Added padding-left to align with the title text -->
        <p class="mb-4 dark:text-gray-300">Please be advised:</p>
        <ul class="list-disc list-inside mb-4 dark:text-gray-300">
          <li><span class="font-bold">Secrets will remain active until they expire.</span></li>
          <li>Any secrets you wish to remove, <a href="#" class="underline">burn them before continuing</a>.</li>
          <li>Deleting your account is <span class="italic">permanent and non-reversible.</span></li>
        </ul>
        <button @click="showDeleteModal = true" class="w-full bg-red-600 hover:bg-red-700 text-white font-bold py-2 px-4 rounded flex items-center justify-center">
          <i class="fas fa-trash-alt mr-2"></i> Permanently Delete Account
        </button>
        <p class="text-sm text-gray-500 dark:text-gray-400 mt-2">Deleting {{ custid }}</p>
      </div>
    </div>

    <p class="mt-6 text-sm text-gray-600 dark:text-gray-400">
      Created {{ secretsCount }} secrets since {{ creationDate }}.
    </p>

    <!-- Delete Account Confirmation Modal -->
    <div v-if="showDeleteModal" class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <form @submit.prevent="submitDeleteAccount" class="w-full max-w-md">
        <div class="bg-white dark:bg-gray-800 p-6 rounded-lg shadow-lg">
          <h3 class="text-xl font-bold mb-4 text-gray-900 dark:text-white">Confirm Account Deletion</h3>
          <p class="mb-4 text-gray-700 dark:text-gray-300">Are you sure you want to permanently delete your account? This action cannot be undone.</p>

          <input type="hidden" name="tabindex" value="destroy" />

          <div class="mb-4">
            <input
              v-model="deletePassword"
              type="password"
              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-brand-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
              autocomplete="confirmation"
              placeholder="Confirm with your password" />
          </div>

          <p v-if="deleteError" class="text-red-500 mb-4">{{ deleteError }}</p>

          <div class="flex justify-end space-x-4">
            <button
              @click="showDeleteModal = false"
              type="button"
              class="px-4 py-2 bg-gray-200 hover:bg-gray-300 text-gray-800 rounded-md focus:outline-none focus:ring-2 focus:ring-gray-400 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600">
              Cancel
            </button>
            <button
              type="submit"
              :disabled="!deletePassword || isDeleting"
              class="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-md focus:outline-none focus:ring-2 focus:ring-red-500 dark:bg-red-700 dark:hover:bg-red-800 flex items-center disabled:opacity-50 disabled:cursor-not-allowed">
              <svg v-if="isDeleting" class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              <svg v-else xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 mr-2" width="20" height="20" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clip-rule="evenodd" />
              </svg>
              {{ isDeleting ? 'Deleting...' : 'Delete Account' }}
            </button>
          </div>

        </div>
      </form>
    </div>

  </div>
</template>

<script setup lang="ts">
import { ref, reactive } from 'vue';
import { Icon } from '@iconify/vue';
import { Cust } from '@/types/onetime';

const custid = window.custid;
const cust: Cust = window.cust as Cust;
const customer_since = window.customer_since;
const shrimp = window.shrimp;

// Props or state management would typically be used here
const accountType = ref(cust.plan.options.name)
const secretsCount = ref(cust.secrets_created)
const creationDate = ref(customer_since)

const currentPassword = ref('');
const newPassword = ref('');
const confirmPassword = ref('');

const showPassword = reactive({
  current: false,
  new: false,
  confirm: false
});

const showDeleteModal = ref(false);
const deletePassword = ref('');
const isDeleting = ref(false);
const deleteError = ref('');

const submitDeleteAccount = async () => {
  isDeleting.value = true;
  deleteError.value = '';

  try {
    // Call the API
    const formData = new URLSearchParams();
    formData.append('confirmation', deletePassword.value);

    const response = await fetch('/api/v1/account/destroy', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: formData.toString(),
    });

    if (!response.ok) {
      const errorResponse = await response.json(); // Parse the JSON from the response
      const errorMessage = errorResponse.message; // Assuming the error message is stored in a property named 'message'
      throw new Error(errorMessage || 'Failed to delete account'); // Throw a new error with the message
    }

    // Account deleted successfully
    showDeleteModal.value = false;

    // Old-school, plain js redirect to the homepage
    window.location.href = '/'

  } catch (error: unknown) {

    if (error instanceof Error) {
      deleteError.value = error.message || 'An error occurred while deleting the account';

    } else {
      console.error("An unexpected error occurred", error);
    }

  } finally {
    isDeleting.value = false;
  }
};

// Define reactive variables
const isUpdating = ref(false);
const updateError = ref('');
const successMessage = ref('');

const updatePassword = async (event: Event) => {
  isUpdating.value = true;
  updateError.value = '';
  successMessage.value = '';

  try {
    // Get the form element from the event
    const form = event.target as HTMLFormElement;

    // Create FormData object from the form
    const formData = new FormData(form);

    // Convert FormData to URLSearchParams
    const urlSearchParams = new URLSearchParams(formData as never);

    // Call the API
    const response = await fetch('/api/v1/account/change-password', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: urlSearchParams.toString(),
    });

    if (!response.ok) {
      if (response.headers.get("content-type")?.includes("application/json")) {
        const errorResponse = await response.json();
        const errorMessage = errorResponse.message;
        throw new Error(errorMessage || 'Failed to update password');
      } else {
        throw new Error(`Please refresh the page and try again.`);
      }
    }

    // Show the success message for a few seconds before redirecting
    successMessage.value = "Password updated successfully.";

    setTimeout(() => {
      window.location.href = '/account';
    }, 3000); // Redirect after 3 seconds

  } catch (error: unknown) {

    if (error instanceof Error) {
      updateError.value = error.message || 'An error occurred while updating the password';

    } else {
      console.error('An unexpected error occurred', error);
    }

  } finally {
    isUpdating.value = false;
  }
};

const togglePassword = (field: 'current' | 'new' | 'confirm') => {
  showPassword[field] = !showPassword[field];
};


</script>
