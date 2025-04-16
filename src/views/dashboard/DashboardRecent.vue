<script setup lang="ts">
  import TableSkeleton from '@/components/closet/TableSkeleton.vue';
  import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
  import EmptyState from '@/components/EmptyState.vue';
  import ErrorDisplay from '@/components/ErrorDisplay.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import SecretMetadataTable from '@/components/secrets/SecretMetadataTable.vue';
  import ToastNotification from '@/components/ui/ToastNotification.vue';
  import { useMetadataList } from '@/composables/useMetadataList';
  import { MetadataRecords } from '@/schemas/api/endpoints';
  import { onMounted, computed, ref, onBeforeUnmount } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  // Define props
  interface Props {}
  defineProps<Props>();

  const { details, recordCount, isLoading, refreshRecords, error } = useMetadataList();
  const sectionId = ref(`dashboard-recent-${Math.random().toString(36).substring(2, 9)}`);
  const lastRefreshed = ref(new Date());
  const refreshInterval = ref<number | null>(null);

  // Toast notification state
  const showToast = ref(false);
  const toastMessage = ref('');

  // Add computed properties for received and not received items
  const receivedItems = computed(() => {
    if (details.value) {
      return details.value.received;
    }
    return [] as MetadataRecords[];
  });

  const notReceivedItems = computed(() => {
    if (details.value) {
      return details.value.notreceived;
    }
    return [] as MetadataRecords[];
  });

  // Method to force refresh
  const handleRefresh = async () => {
    toastMessage.value = t('web.LABELS.refreshing');
    showToast.value = true;
    await refreshRecords();
    lastRefreshed.value = new Date();
    setTimeout(() => {
      showToast.value = false;
    }, 1500);
  };

  // Set up auto-refresh interval
  onMounted(() => {
    refreshRecords();
    refreshInterval.value = window.setInterval(() => {
      // Auto-refresh status every 5 minutes
      refreshRecords();
      lastRefreshed.value = new Date();
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
  <div>
    <DashboardTabNav />

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
        <!-- Section header with count and refresh button -->
        <div
          v-if="recordCount > 0"
          class="mb-4 flex items-center justify-between">
          <div>
            <h2
              id="dashboard-recent-heading"
              class="text-xl font-medium text-gray-700 dark:text-gray-200">
              {{ $t('web.LABELS.title_recent_secrets') }}
            </h2>
          </div>

          <div class="flex items-center gap-3">
            <span class="text-sm text-gray-500 dark:text-gray-400">
              {{ $t('web.LABELS.items_count', { count: recordCount }) }}
            </span>
            <button
              @click="handleRefresh"
              class="flex items-center gap-1 rounded p-1.5
                text-gray-500 hover:bg-gray-100 hover:text-gray-700
                dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-200"
              :aria-label="$t('web.LABELS.refresh')"
              type="button">
              <OIcon
                collection="heroicons"
                name="arrow-path"
                class="size-4" />
              <span class="sr-only">{{ $t('web.LABELS.refresh') }}</span>
            </button>
          </div>
        </div>

        <!-- Content area -->
        <div
          role="region"
          aria-live="polite">
          <SecretMetadataTable
            v-if="recordCount > 0"
            :not-received="notReceivedItems"
            :received="receivedItems"
            :is-loading="isLoading"
            :aria-labelledby="'dashboard-recent-heading'" />
          <EmptyState
            v-else
            action-route="/"
            :action-text="$t('create-a-secret')">
            <template #title>
              {{ $t('web.dashboard.title_no_recent_secrets') }}
            </template>
            <template #description>
              <div>{{ $t('web.dashboard.get-started-by-creating-your-first-secret') }}</div>
              <div>{{ $t('theyll-appear-here-once-youve-shared-them') }}</div>
            </template>
          </EmptyState>
        </div>
      </div>

      <!-- Toast notification for actions -->
      <ToastNotification
        :show="showToast"
        :message="toastMessage"
        aria-live="polite" />
    </section>
  </div>
</template>
