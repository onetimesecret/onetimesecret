<!-- src/apps/workspace/components/account/AccountDeleteButtonWithModalForm.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import { useFormSubmission } from '@/shared/composables/useFormSubmission';
import { Customer } from '@/schemas/models';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { ref } from 'vue';

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
  url: '/api/account/account/destroy',
  successMessage: t('web.account.account_deleted_successfully'),
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
    {{ t('web.account.please_be_advised') }}
  </p>
  <ul class="mb-4 list-inside list-disc dark:text-gray-300">
    <li><span class="font-bold">{{ t('web.account.secrets_will_remain_active_until_they_expire') }}</span></li>
    <li>
      {{ t('web.account.any_secrets_you_wish_to_remove') }} <span
        class="underline">{{ t('web.account.burn_them_before_continuing') }}</span>.
    </li>
    <li>{{ t('web.account.deleting_your_account_is') }} <span class="italic">{{ t('web.account.permanent_and_non_reversible') }}</span></li>
  </ul>
  <button
    @click="openDeleteModal"
    class="group flex w-full items-center justify-center rounded bg-red-600 px-4 py-2 font-bold text-white transition-all hover:bg-red-700 hover:shadow-lg hover:shadow-red-500/25">
    <!-- no-symbol: Reserved exclusively for destructive/irreversible actions -->
    <OIcon
      collection="heroicons"
      name="no-symbol-solid"
      class="mr-2 size-5 transition-transform group-hover:scale-110"
      aria-hidden="true" />
    {{ t('web.account.permanently_delete_account') }}
  </button>
  <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
    {{ t('web.account.deleting_cust_custid', [cust?.extid]) }}
  </p>

  <!-- Delete Account Confirmation Modal -->
  <div
    v-if="showDeleteModal"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
    <form
      @submit.prevent="submitDeleteAccount"
      class="w-full max-w-md">
      <input
        type="hidden"
        name="shrimp"
        :value="csrfStore.shrimp" />

      <div class="rounded-lg bg-white p-6 shadow-lg dark:bg-gray-800">
        <h3 class="mb-4 text-xl font-bold text-gray-900 dark:text-white">
          {{ t('web.account.confirm_account_deletion') }}
        </h3>
        <p class="mb-4 text-gray-700 dark:text-gray-300">
          {{ t('web.account.are_you_sure_you_want_to_permanently_delete_your') }}
        </p>

        <input
          type="hidden"
          name="tabindex"
          value="destroy" />

        <div class="mb-4">
          <input
            v-model="deletePassword"
            name="confirmation"
            type="password"
            class="w-full rounded-md border border-gray-300 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
            autocomplete="confirmation"
            :placeholder="t('web.account.confirm_with_your_password')" />
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
            {{ t('web.COMMON.word_cancel') }}
          </button>
          <button
            type="submit"
            :disabled="!deletePassword || isDeleting"
            class="group flex items-center rounded-md bg-red-600 px-4 py-2 text-white transition-all hover:bg-red-700 hover:shadow-lg hover:shadow-red-500/25 focus:outline-none focus:ring-2 focus:ring-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-red-700 dark:hover:bg-red-800">
            <OIcon
              v-if="isDeleting"
              collection="heroicons"
              name="arrow-path"
              class="-ml-1 mr-3 size-5 animate-spin"
              aria-hidden="true" />
            <!-- no-symbol: Reserved exclusively for destructive/irreversible actions -->
            <OIcon
              v-else
              collection="heroicons"
              name="no-symbol-solid"
              class="mr-2 size-5 transition-transform group-hover:scale-110"
              aria-hidden="true" />
            {{ isDeleting ? t('web.account.deleting_ellipsis') : t('web.account.delete_account') }}
          </button>
        </div>
      </div>
    </form>
  </div>
</template>
