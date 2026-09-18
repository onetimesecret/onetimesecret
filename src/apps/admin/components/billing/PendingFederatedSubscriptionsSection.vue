<!-- src/apps/admin/components/billing/PendingFederatedSubscriptionsSection.vue -->

<script setup lang="ts">
  import { DataTable, KitPagination } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminPendingFederatedSubscriptions } from '@/apps/admin/stores/useAdminPendingFederatedSubscriptions';
  import type { ColonelPendingFederatedSubscription } from '@/schemas/api/internal/responses/colonel-billing';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Read-only pending federation inventory. Its correlation cell never guesses:
   * `no_correlation` and `expired` are distinct unavailable states, not outcomes.
   */
  const { t } = useI18n();
  const store = useAdminPendingFederatedSubscriptions();
  const { subscriptions, pagination, loading, error, capped } = storeToRefs(store);

  // Pending records intentionally expose no email-hash identifier. Add a
  // page-local render key rather than leaking one just to satisfy table keys.
  const tableRows = computed(() =>
    subscriptions.value.map((subscription, index) => ({
      ...subscription,
      row_key: `${subscription.received_at ?? 'unknown'}:${index}`,
    }))
  );

  const columns = computed<DataTableColumn<ColonelPendingFederatedSubscription>[]>(() => [
    { key: 'status', label: t('web.admin.billing.pendingFederated.columns.status') },
    { key: 'planid', label: t('web.admin.billing.pendingFederated.columns.planid') },
    { key: 'region', label: t('web.admin.billing.pendingFederated.columns.region') },
    { key: 'received', label: t('web.admin.billing.pendingFederated.columns.received') },
    { key: 'webhook', label: t('web.admin.billing.pendingFederated.columns.webhook') },
  ]);

  function timestamp(value: number | null): string {
    return value === null ? '—' : formatDisplayDateTime(new Date(value * 1000));
  }

  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(targetPage);
    } catch {
      // The section retains error state and offers its own retry control.
    }
  }

  function onPerPageChange(perPage: number): void {
    store.perPage = perPage;
    fetchPage(1);
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <section data-testid="billing-pending-federated-subscriptions">
    <div class="mb-3 flex flex-wrap items-baseline justify-between gap-2">
      <div>
        <h3 class="text-lg font-medium text-gray-900 dark:text-white">
          {{ t('web.admin.billing.pendingFederated.title') }}
          <span
            v-if="pagination"
            class="ml-1 text-sm font-normal text-gray-500 tabular-nums dark:text-gray-400"
            data-testid="billing-pending-federated-count">
            ({{ pagination.total_count }})
          </span>
        </h3>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.billing.pendingFederated.description') }}
        </p>
      </div>
    </div>

    <div
      class="mb-4 rounded-md border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-700 dark:border-gray-800 dark:bg-gray-800/40 dark:text-gray-300"
      role="status"
      data-testid="billing-pending-federated-retention">
      {{ t('web.admin.billing.pendingFederated.correlationRetention') }}
    </div>

    <div
      v-if="error"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="billing-pending-federated-error">
      <span class="text-sm text-red-800 dark:text-red-200">{{
        t('web.admin.billing.pendingFederated.loadError')
      }}</span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        data-testid="billing-pending-federated-retry"
        @click="fetchPage(pagination?.page ?? 1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.billing.retry') }}
      </button>
    </div>

    <div
      v-if="capped"
      class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800 dark:border-amber-900/50 dark:bg-amber-900/20 dark:text-amber-200"
      role="status"
      data-testid="billing-pending-federated-capped">
      {{ t('web.admin.billing.pendingFederated.capped') }}
    </div>

    <div
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <DataTable
        :columns="columns"
        :rows="tableRows"
        row-key="row_key"
        :loading="loading"
        :empty-text="t('web.admin.billing.pendingFederated.empty')"
        testid="billing-pending-federated-table">
        <template #cell-status="{ row }">{{ row.subscription_status || '—' }}</template>
        <template #cell-planid="{ row }"
          ><span class="font-mono text-xs text-gray-900 dark:text-white">{{
            row.planid || t('web.admin.billing.pendingFederated.unresolvedPlan')
          }}</span></template
        >
        <template #cell-region="{ row }">{{ row.region || '—' }}</template>
        <template #cell-received="{ row }"
          ><span class="text-sm text-gray-500 tabular-nums dark:text-gray-400">{{
            timestamp(row.received_at)
          }}</span></template
        >
        <template #cell-webhook="{ row }">
          <template v-if="row.source_webhook.state === 'available'">
            <span class="block">{{ row.source_webhook.processing_status || '—' }}</span>
            <span class="block text-xs text-gray-500 dark:text-gray-400">{{
              row.source_webhook.outcome || '—'
            }}</span>
          </template>
          <span
            v-else
            class="text-sm text-gray-500 dark:text-gray-400"
            :data-testid="`billing-pending-federated-webhook-${row.source_webhook.state}`">
            {{ t(`web.admin.billing.pendingFederated.webhook.${row.source_webhook.state}`) }}
          </span>
        </template>
      </DataTable>
    </div>

    <KitPagination
      v-if="pagination"
      :pagination="pagination"
      :loading="loading"
      class="mt-4"
      @update:page="fetchPage"
      @update:per-page="onPerPageChange" />
  </section>
</template>
