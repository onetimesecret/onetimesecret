<template>
  <div class="max-w-2xl p-4 mx-auto">
    <h1 class="dark:text-white mb-6 text-3xl font-bold">Your Account</h1>
    <p class="dark:text-gray-300 mb-4 text-lg">Account type: {{ accountType }}</p>

    <!-- API KEY -->
    <div class="dark:bg-gray-800 p-6 mb-6 bg-white rounded-lg shadow">
      <h2 class="dark:text-white flex items-center mb-4 text-xl font-semibold">
        <i class="fas fa-exclamation-triangle mr-2 text-red-500"></i>
        <span class="flex-1">API Key</span>
      </h2>
      <div class="pl-3">
        <form @submit.prevent="generateAPIKey">
          <input type="hidden"
                 name="shrimp"
                 :value="shrimp" />

          <APIKeyCard :token="apitoken" />

          <div v-if="apiKeyError"
               class="mb-4 text-red-500">{{ apiKeyError }}</div>
          <div v-if="apiKeySuccess"
               class="mb-4 text-green-500">{{ apiKeySuccess }}</div>

          <button type="submit"
                  class="hover:bg-gray-600 flex items-center justify-center w-full px-4 py-2 text-white bg-gray-500 rounded">
            <i class="fas fa-trash-alt mr-2"></i> {{ isGeneratingAPIKey ? 'Generating...' : 'Generate Key' }}
          </button>
          <p class="dark:text-gray-400 mt-2 text-sm text-gray-500"></p>
        </form>
      </div>
    </div>

    <!-- BILLING INFO -->
    <AccountBillingSection
      :stripe-customer="stripe_customer"
      :stripe-subscriptions="stripe_subscriptions"
    />


    <!-- PASSWORD CHANGE -->
    <div class="dark:bg-gray-800 p-6 mb-6 bg-white rounded-lg shadow">
      <h2 class="dark:text-white flex items-center mb-4 text-xl font-semibold">
        <i class="fas fa-lock mr-2"></i> Update Password
      </h2>
      <div class="pl-3"> <!-- Added padding-left to align with the title text -->
        <form @submit.prevent="updatePassword">
          <input type="hidden"
                 name="shrimp"
                 :value="shrimp" />

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
                   class="dark:text-gray-300 block text-sm font-medium text-gray-700">Current Password</label>

            <div class="relative">
              <input :type="showPassword.current ? 'text' : 'password'"
                     name="currentp"
                     id="currentPassword"
                     v-model="currentPassword"
                     required
                     tabindex="1"
                     autocomplete="current-password"
                     aria-label="Current Password"
                     aria-labelledby="currentPasswordLabel"
                     class="dark:border-gray-600 focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:bg-gray-700 dark:text-white block w-full pr-10 mt-1 border-gray-300 rounded-md shadow-sm">
              <button type="button"
                      @click="togglePassword('current')"
                      class="absolute inset-y-0 right-0 flex items-center pr-3">
                <Icon :icon="showPassword.current ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
                      class="dark:text-gray-100 w-5 h-5 text-gray-400"
                      aria-hidden="true" />
              </button>
            </div>

          </div>
          <div class="relative mb-4">
            <label for="newPassword"
                   id="newPasswordLabel"
                   class="dark:text-gray-300 block text-sm font-medium text-gray-700">New Password</label>

            <div class="relative">
              <input :type="showPassword.new ? 'text' : 'password'"
                     name="newp"
                     id="newPassword"
                     v-model="newPassword"
                     required
                     tabindex="2"
                     autocomplete="new-password"
                     aria-label="New Password"
                     aria-labelledby="newPasswordLabel"
                     class="dark:border-gray-600 focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:bg-gray-700 dark:text-white block w-full pr-10 mt-1 border-gray-300 rounded-md shadow-sm">
              <button type="button"
                      @click="togglePassword('new')"
                      class="hover:text-gray-600 dark:text-gray-300 dark:hover:text-gray-100 absolute inset-y-0 right-0 flex items-center pr-3 text-gray-400">
                <Icon :icon="showPassword.new ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
                      class="dark:text-gray-100 w-5 h-5 text-gray-400"
                      aria-hidden="true" />
              </button>
            </div>

          </div>
          <div class="relative mb-4">
            <label for="confirmPassword"
                   id="confirmPasswordlabel"
                   class="dark:text-gray-300 block text-sm font-medium text-gray-700">Confirm</label>

            <div class="relative">
              <input :type="showPassword.confirm ? 'text' : 'password'"
                     name="newp2"
                     id="confirmPassword"
                     v-model="confirmPassword"
                     required
                     tabindex="3"
                     autocomplete="confirm-password"
                     aria-label="New Password"
                     aria-labelledby="confirmPasswordlabel"
                     class="dark:border-gray-600 focus:border-brand-500 focus:ring focus:ring-brand-500 focus:ring-opacity-50 dark:bg-gray-700 dark:text-white block w-full pr-10 mt-1 border-gray-300 rounded-md shadow-sm">
              <button type="button"
                      @click="togglePassword('confirm')"
                      class="absolute inset-y-0 right-0 flex items-center pr-3">
                <Icon :icon="showPassword.confirm ? 'heroicons-solid:eye' : 'heroicons-outline:eye-off'"
                      class="dark:text-gray-100 w-5 h-5 text-gray-400"
                      aria-hidden="true" />
              </button>
            </div>

          </div>

          <div v-if="passwordError"
               class="mb-4 text-red-500">{{ passwordError }}</div>
          <div v-if="passwordSuccess"
               class="mb-4 text-green-500">{{ passwordSuccess }}</div>

          <button type="submit"
                  class="hover:bg-gray-600 flex items-center justify-center w-full px-4 py-2 text-white bg-gray-500 rounded">
            <i class="fas fa-save mr-2"></i> {{ isUpdatingPassword ? 'Updating...' : 'Update Password' }}
          </button>
        </form>
      </div>
    </div>

    <div class="dark:bg-gray-800 p-6 bg-white rounded-lg shadow">
      <h2 class="dark:text-white flex items-center mb-4 text-xl font-semibold">
        <i class="fas fa-exclamation-triangle mr-2 text-red-500"></i>
        <span class="flex-1">Delete Account</span>
      </h2>
      <div class="pl-3"> <!-- Added padding-left to align with the title text -->
        <p class="dark:text-gray-300 mb-4">Please be advised:</p>
        <ul class="dark:text-gray-300 mb-4 list-disc list-inside">
          <li><span class="font-bold">Secrets will remain active until they expire.</span></li>
          <li>Any secrets you wish to remove, <a href="#"
               class="underline">burn them before continuing</a>.</li>
          <li>Deleting your account is <span class="italic">permanent and non-reversible.</span></li>
        </ul>
        <button @click="openDeleteModal"
                class="hover:bg-red-700 flex items-center justify-center w-full px-4 py-2 font-bold text-white bg-red-600 rounded">
          <i class="fas fa-trash-alt mr-2"></i> Permanently Delete Account
        </button>
        <p class="dark:text-gray-400 mt-2 text-sm text-gray-500">Deleting {{ custid }}</p>
      </div>
    </div>

    <p class="dark:text-gray-400 mt-6 text-sm text-gray-600">
      Created {{ secretsCount }} secrets since {{ creationDate }}.
    </p>

    <!-- Delete Account Confirmation Modal -->
    <div v-if="showDeleteModal"
         class="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-50">
      <form @submit.prevent="submitDeleteAccount"
            class="w-full max-w-md">
        <input type="hidden"
               name="shrimp"
               :value="shrimp" />

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

  </div>
</template>

<script setup lang="ts">
import AccountBillingSection from '@/components/AccountBillingSection.vue';
import APIKeyCard from '@/components/APIKeyCard.vue';
import { ApiKeyApiResponse, Cust } from '@/types/onetime';
import { useFormSubmission } from '@/utils/formSubmission';
import { Icon } from '@iconify/vue';
import { reactive, ref } from 'vue';

const custid = window.custid;
const cust: Cust = window.cust as Cust;
const customer_since = window.customer_since;
const shrimp = ref(window.shrimp);
const apitoken = ref(window.apitoken);

const stripe_customer = ref(window.stripe_customer);
const stripe_subscriptions = ref(window.stripe_subscriptions);

// Props or state management would typically be used here
const accountType = ref(cust.plan?.options?.name)
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


const handleShrimp = (freshShrimp: string) => {
  shrimp.value = freshShrimp;
}
const showDeleteModal = ref(false);
const deletePassword = ref('');

const {
  isSubmitting: isDeleting,
  error: deleteError,
  success: deleteSuccess,
  submitForm: submitDeleteAccount
} = useFormSubmission({
  url: '/api/v1/account/destroy',
  successMessage: 'Account deleted successfully.',
  onSuccess: () => {
    showDeleteModal.value = false;
    window.location.href = '/';
  },
  handleShrimp: handleShrimp,
});


const openDeleteModal = () => {
  showDeleteModal.value = true;
};

const closeDeleteModal = () => {
  showDeleteModal.value = false;
  deletePassword.value = '';
};


const {
  isSubmitting: isGeneratingAPIKey,
  error: apiKeyError,
  success: apiKeySuccess,
  submitForm: generateAPIKey
} = useFormSubmission({
  url: '/api/v1/account/apikey',
  successMessage: 'Key generated.',
  onSuccess: async (data: ApiKeyApiResponse) => {
    // @ts-expect-error "data.record" is defined only as BaseApiRecord
    apitoken.value = (data as ApiRecordResponse).record?.apikey || '';
  },
  handleShrimp: handleShrimp,
});

const {
  isSubmitting: isUpdatingPassword,
  error: passwordError,
  success: passwordSuccess,
  submitForm: updatePassword
} = useFormSubmission({
  url: '/api/v1/account/change-password',
  successMessage: 'Password updated successfully.',
  handleShrimp: handleShrimp,
});

const togglePassword = (field: 'current' | 'new' | 'confirm') => {
  showPassword[field] = !showPassword[field];
};

</script>
