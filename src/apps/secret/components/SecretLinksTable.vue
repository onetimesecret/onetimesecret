<!-- src/apps/secret/components/SecretLinksTable.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import ToastNotification from '@/shared/components/ui/ToastNotification.vue';
import type { RecentSecretRecord } from '@/shared/composables/useRecentSecrets';
import { computed, ref, onMounted, onBeforeUnmount, provide } from 'vue';

import SecretLinksTableRow from './SecretLinksTableRow.vue';

const { t } = useI18n();

const props = defineProps<{
  records: RecentSecretRecord[];
  ariaLabelledBy?: string;
}>();

const emit = defineEmits<{
  'update:memo': [id: string, memo: string];
}>();

const handleUpdateMemo = (id: string, memo: string) => {
  emit('update:memo', id, memo);
};

// Toast notification state
const showToast = ref(false);
const toastMessage = ref('');
const refreshInterval = ref<number | null>(null);
const lastRefreshed = ref(new Date());

// Trigger for child components to refresh
const refreshTrigger = ref(0);

// Provide the refresh trigger to child components
provide('refreshTrigger', refreshTrigger);

const hasSecrets = computed(() => props.records.length > 0);

// Sort secrets by creation time (most recent first)
const sortedSecrets = computed(() =>
  [...props.records].sort(
    (a, b) => b.createdAt.getTime() - a.createdAt.getTime()
  )
);

const handleCopy = () => {
  // Copy feedback is now handled by the tooltip in SecretLinksTableRow
};

const handleBurn = (record: RecentSecretRecord) => {
  // Here you would add logic to delete the message, e.g.,
  // through a store or service call
  void record; // Suppress unused variable warning until burn logic is implemented
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
  <div class="mt-6">
    <!-- No secrets state -->
    <div
      v-if="!hasSecrets"
      class="flex flex-col items-center justify-center rounded-xl border border-gray-200
        bg-gray-50/50 py-10 dark:border-gray-700/50 dark:bg-slate-800/20"
      role="status">
      <OIcon
        collection="heroicons"
        name="document-text"
        class="mb-3 size-12 text-gray-300 dark:text-gray-600"
        aria-hidden="true" />
      <p class="text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.dashboard.title_no_recent_secrets') }}
      </p>
    </div>

    <!-- Card list with secrets -->
    <div
      v-else
      class="space-y-3"
      role="list"
      :aria-labelledby="ariaLabelledBy">
      <span class="sr-only">{{ t('web.LABELS.caption_recent_secrets') }}</span>

      <SecretLinksTableRow
        v-for="(record, idx) in sortedSecrets"
        :key="record.id"
        :record="record"
        :index="sortedSecrets.length - idx"
        @copy="handleCopy"
        @delete="handleBurn"
        @update:memo="handleUpdateMemo" />
    </div>

    <ToastNotification
      :show="showToast"
      :message="toastMessage"
      aria-live="polite" />
  </div>
</template>
