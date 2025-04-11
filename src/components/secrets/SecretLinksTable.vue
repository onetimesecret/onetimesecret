<script setup lang="ts">
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { ref } from 'vue';
  import SecretLinksTableRow from './SecretLinksTableRow.vue';
  import ToastNotification from '@/components/ui/ToastNotification.vue';

  defineProps<{
    concealedMessages: ConcealedMessage[];
  }>();

  // Toast notification state
  const showToast = ref(false);
  const toastMessage = ref('');

  const handleCopy = () => {
    toastMessage.value = 'Copied to clipboard';
    showToast.value = true;
    setTimeout(() => {
      showToast.value = false;
    }, 1500);
  };

  const handleBurn = (concealedMessage: ConcealedMessage) => {
    // Here you would add logic to delete the message, e.g.,
    // through a store or service call
    console.log('Deleting message', concealedMessage.id);
    toastMessage.value = 'Message deleted';
    showToast.value = true;
    setTimeout(() => {
      showToast.value = false;
    }, 1500);
  };
</script>

<template>
  <div
    class="relative overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-slate-900">
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
        <thead class="bg-gray-50 dark:bg-slate-800">
          <tr>
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400">
              {{ $t('web.LABELS.secret_link') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400">
              {{ $t('details') }}
            </th>
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400">
                {{ $t('web.LABELS.actions') }}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
          <SecretLinksTableRow
            v-for="concealedMessage in concealedMessages"
            :key="concealedMessage.id"
            :concealed-message="concealedMessage"
            @copy="handleCopy"
            @delete="handleBurn"
          />
        </tbody>
      </table>
    </div>

    <ToastNotification
      :show="showToast"
      :message="toastMessage"
    />
  </div>
</template>
