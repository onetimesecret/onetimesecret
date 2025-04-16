<!-- src/components/secrets/SecretLinksTable.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import ToastNotification from '@/components/ui/ToastNotification.vue';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { computed, ref, onMounted, onBeforeUnmount, provide } from 'vue';
  import { useI18n } from 'vue-i18n';
  //import { useSecretStore } from '@/stores/secretStore';

  import SecretLinksTableRow from './SecretLinksTableRow.vue';

  const { t } = useI18n();
  //const secretStore = useSecretStore();

  const props = defineProps<{
    concealedMessages: ConcealedMessage[];
    ariaLabelledBy?: string;
  }>();

  // Toast notification state
  const showToast = ref(false);
  const toastMessage = ref('');
  const refreshInterval = ref<number | null>(null);
  const lastRefreshed = ref(new Date());

  // Trigger for child components to refresh
  const refreshTrigger = ref(0);

  // Provide the refresh trigger to child components
  provide('refreshTrigger', refreshTrigger);

  const hasSecrets = computed(() => props.concealedMessages.length > 0);

  // Sort secrets by creation time (most recent first)
  const sortedSecrets = computed(() => {
    return [...props.concealedMessages].sort((a, b) => {
      // Sort by creation time, newest first
      return b.clientInfo.createdAt.getTime() - a.clientInfo.createdAt.getTime();
    });
  });

  const handleCopy = () => {
    // Copy feedback is now handled by the tooltip in SecretLinksTableRow
  };

  const handleBurn = (concealedMessage: ConcealedMessage) => {
    // Here you would add logic to delete the message, e.g.,
    // through a store or service call
    console.log('Deleting message', concealedMessage.id);
    toastMessage.value = t('web.secrets.messageDeleted');
    showToast.value = true;
    setTimeout(() => {
      showToast.value = false;
    }, 1500);
  };

  // Method to force refresh all statuses
  const refreshAllStatuses = async () => {
    lastRefreshed.value = new Date();
    // Increment the refresh trigger to notify all child components
    refreshTrigger.value++;
  };

  // Set up the interval to update the "last refreshed" indicator
  onMounted(() => {
    refreshInterval.value = window.setInterval(() => {
      // Auto-refresh status every 5 minutes
      refreshAllStatuses();
    }, 300000); // Every 5 minutes
  });

  // Clean up
  onBeforeUnmount(() => {
    if (refreshInterval.value) {
      clearInterval(refreshInterval.value);
    }
  });
</script>

<template>
  <div class="mt-8">
    <!-- No secrets state -->
    <!-- prettier-ignore-attribute class -->
    <div
      v-if="!hasSecrets"
      class="flex flex-col items-center justify-center
        rounded-lg border border-gray-200 bg-gray-50 py-8 dark:border-gray-700
        dark:bg-slate-800/30"
      role="status">
      <OIcon
        collection="heroicons"
        name="document-text"
        class="mb-3 size-10 text-gray-400 dark:text-gray-500"
        aria-hidden="true" />
      <p class="text-gray-500 dark:text-gray-400">
        {{ $t('web.dashboard.title_no_recent_secrets') }}
      </p>
    </div>

    <!-- Table with secrets -->
    <!-- prettier-ignore-attribute class -->
    <div
      v-else
      class="relative overflow-hidden
        rounded-lg border border-gray-200 bg-white opacity-90 shadow-sm
        dark:border-gray-700 dark:bg-slate-900">
      <div class="overflow-x-auto">
        <!-- Table Header with Refresh Button -->
        <div
          v-if="false"
          class="flex justify-between bg-gray-50 p-2 dark:bg-slate-800">
          <span class="text-xs text-gray-500 dark:text-gray-400">
            {{ $t('web.LABELS.last_refreshed') }}: {{ lastRefreshed.toLocaleTimeString() }}
          </span>
          <!-- prettier-ignore-attribute class -->
          <button
            @click="refreshAllStatuses"
            class="flex items-center text-xs
              text-blue-500 hover:text-blue-600
              dark:text-blue-400 dark:hover:text-blue-300">
            <OIcon
              collection="heroicons"
              name="arrow-path"
              class="mr-1 size-4" />
            {{ $t('web.LABELS.refresh') }}
          </button>
        </div>

        <!-- Secrets Table -->
        <table
          class="min-w-full divide-y divide-gray-200 dark:divide-gray-700"
          :aria-labelledby="ariaLabelledBy">
          <caption class="sr-only">
            {{ $t('web.LABELS.caption_recent_secrets') }}
          </caption>
          <thead class="bg-gray-50 dark:bg-slate-800">
            <tr>
              <!-- prettier-ignore-attribute class -->
              <th
                scope="col"
                class="px-6 py-2.5 text-left text-xs font-medium uppercase tracking-wider
                  text-gray-700 dark:text-gray-400">
                {{ $t('web.LABELS.receipts') }}
              </th>
              <!-- prettier-ignore-attribute class -->
              <th
                scope="col"
                class="hidden px-6 py-2.5 text-left text-xs font-medium uppercase tracking-wider
                  text-gray-700 dark:text-gray-400 sm:table-cell">
                {{ $t('web.LABELS.details') }}
              </th>
              <!-- prettier-ignore-attribute class -->
              <th
                scope="col"
                class="px-6 py-2.5 text-right text-xs font-medium uppercase tracking-wider
                  text-gray-700 dark:text-gray-400">
                {{ $t('web.LABELS.share') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <SecretLinksTableRow
              v-for="concealedMessage in sortedSecrets"
              :key="concealedMessage.id"
              :concealed-message="concealedMessage"
              @copy="handleCopy"
              @delete="handleBurn" />
          </tbody>
        </table>
      </div>

      <ToastNotification
        :show="showToast"
        :message="toastMessage"
        aria-live="polite" />
    </div>
  </div>
</template>
