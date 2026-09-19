<!-- src/apps/workspace/dashboard/DashboardRecent.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import TableSkeleton from '@/shared/components/closet/TableSkeleton.vue';
  import EmptyState from '@/shared/components/ui/EmptyState.vue';
  import ErrorDisplay from '@/shared/components/ui/ErrorDisplay.vue';
  import SecretReceiptTable from '@/apps/secret/components/SecretReceiptTable.vue';
  import { useBackgroundRefresh } from '@/shared/composables/useBackgroundRefresh';
  import { useReceiptList } from '@/shared/composables/useReceiptList';
  import { onMounted, computed, ref } from 'vue';

  // Define props
  interface Props {}
  defineProps<Props>();

  const { t } = useI18n(); // auto-import
  const { details, recordCount, isLoading, refreshRecords, refreshInBackground, error } =
    useReceiptList();

  const sectionId = ref(`dashboard-recent-${Math.random().toString(36).substring(2, 9)}`);

  // Add computed properties for revealed and pending receipts
  const revealedReceipts = computed(() => details.value?.revealed_receipts ?? []);
  const pendingReceipts = computed(() => details.value?.pending_receipts ?? []);

  // Statuses refresh every 5 minutes while the tab is visible, and when it
  // becomes visible again. Those requests are passive: an unattended dashboard
  // must still reach its inactivity deadline.
  const backgroundRefresh = useBackgroundRefresh(refreshInBackground);

  // The load on arrival is navigation: an ordinary, active request.
  onMounted(() => {
    refreshRecords();
    backgroundRefresh.start();
  });
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <section
      :id="sectionId"
      aria-labelledby="dashboard-recent-heading"
      class="mt-6">
      <ErrorDisplay
        v-if="error"
        :error="error" />

      <div v-else-if="isLoading">
        <TableSkeleton />
      </div>

      <div v-else>
        <!-- Section header with count -->
        <div
          v-if="recordCount > 0"
          class="mb-4 flex items-center justify-between">
          <!-- prettier-ignore-attribute class -->
          <div>
            <h2
              id="dashboard-recent-heading"
              class="text-lg font-medium text-gray-600 dark:text-gray-300">
              {{ t('web.LABELS.title_recent_secrets') }}
            </h2>
          </div>

          <div
            class="flex items-center gap-3">
            <span class="text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.LABELS.items_count', { count: recordCount }) }}
            </span>
          </div>
        </div>

        <!-- Content area -->
        <div
          role="region"
          aria-live="polite">
          <SecretReceiptTable
            v-if="recordCount > 0"
            :pending-receipts="pendingReceipts"
            :revealed-receipts="revealedReceipts"
            :is-loading="isLoading"
            :aria-labelledby="'dashboard-recent-heading'" />
          <EmptyState
            :showAction="true"
            v-else
            action-route="/"
            :action-text="t('web.secrets.create_a_secret')">
            <template #title>
              {{ t('web.dashboard.title_no_recent_secrets') }}
            </template>
            <template #description>
              <div>{{ t('web.dashboard.get_started_by_creating_your_first_secret') }}</div>
              <div>{{ t('web.secrets.theyll_appear_here_once_youve_shared_them') }}</div>
            </template>
          </EmptyState>
        </div>
      </div>
    </section>
  </div>
</template>
