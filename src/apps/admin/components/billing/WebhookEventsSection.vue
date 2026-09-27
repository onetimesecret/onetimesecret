<!-- src/apps/admin/components/billing/WebhookEventsSection.vue -->

<script setup lang="ts">
  import { DataTable, DetailDrawer, KitPagination } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import {
    WEBHOOK_EVENTS_URL,
    useAdminWebhookEvents,
  } from '@/apps/admin/stores/useAdminWebhookEvents';
  import {
    colonelWebhookEventDetailResponseSchema,
    type ColonelWebhookEvent,
  } from '@/schemas/api/internal/responses/colonel-billing';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Read-only local webhook log. The drawer deliberately renders only the API
   * contract's operational allow-list; Stripe payloads and replay stay CLI-only.
   */
  const { t } = useI18n();
  const store = useAdminWebhookEvents();
  const { events, pagination, loading, error, capped, staleCount } = storeToRefs(store);

  const columns = computed<DataTableColumn<ColonelWebhookEvent>[]>(() => [
    { key: 'eventId', label: t('web.admin.billing.webhookEvents.columns.eventId') },
    { key: 'type', label: t('web.admin.billing.webhookEvents.columns.type') },
    { key: 'status', label: t('web.admin.billing.webhookEvents.columns.status') },
    { key: 'received', label: t('web.admin.billing.webhookEvents.columns.received') },
    { key: 'outcome', label: t('web.admin.billing.webhookEvents.columns.outcome') },
    { key: 'actions', label: '', align: 'right' },
  ]);

  function timestamp(value: number | null | undefined): string {
    return value == null ? '—' : formatDisplayDateTime(new Date(value * 1000));
  }

  function statusClass(status: string | null): string {
    if (status === 'success')
      return 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200';
    if (status === 'failed') return 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200';
    if (status === 'retrying')
      return 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-200';
    return 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300';
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

  const drawerOpen = ref(false);
  const selectedEvent = ref<ColonelWebhookEvent | null>(null);
  const detailUrl = (): string =>
    `${WEBHOOK_EVENTS_URL}/${encodeURIComponent(selectedEvent.value?.event_id ?? '')}`;
  const {
    data: detailData,
    loading: detailLoading,
    error: detailError,
    validationError: detailValidationError,
    notFound: detailNotFound,
    load: loadDetail,
  } = useResourceFetch({
    url: detailUrl,
    schema: colonelWebhookEventDetailResponseSchema,
    context: 'ColonelWebhookEventDetailResponse',
  });
  const detail = computed(() => detailData.value?.record ?? null);
  const detailMetadata = computed(() => detailData.value?.details ?? null);
  const detailFailed = computed(
    () =>
      (detailError.value !== null && !detailNotFound.value) || detailValidationError.value !== null
  );

  function openDetail(event: ColonelWebhookEvent): void {
    selectedEvent.value = event;
    drawerOpen.value = true;
    loadDetail().catch(() => {});
  }

  function closeDetail(): void {
    drawerOpen.value = false;
    selectedEvent.value = null;
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <section data-testid="billing-webhook-events">
    <div class="mb-3 flex flex-wrap items-baseline justify-between gap-2">
      <div>
        <h3 class="text-lg font-medium text-gray-900 dark:text-white">
          {{ t('web.admin.billing.webhookEvents.title') }}
          <span
            v-if="pagination"
            class="ml-1 text-sm font-normal text-gray-500 tabular-nums dark:text-gray-400"
            data-testid="billing-webhook-events-count">
            ({{ pagination.total_count }})
          </span>
        </h3>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.billing.webhookEvents.description') }}
        </p>
      </div>
    </div>

    <div
      class="mb-4 rounded-md border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-700 dark:border-gray-800 dark:bg-gray-800/40 dark:text-gray-300"
      role="status"
      data-testid="billing-webhook-events-retention">
      {{ t('web.admin.billing.webhookEvents.retention') }}
    </div>

    <div
      v-if="error"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="billing-webhook-events-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.billing.webhookEvents.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        data-testid="billing-webhook-events-retry"
        @click="fetchPage(pagination?.page ?? 1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.billing.retry') }}
      </button>
    </div>

    <div
      v-if="capped || staleCount > 0"
      class="mb-4 flex flex-col gap-1 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800 dark:border-amber-900/50 dark:bg-amber-900/20 dark:text-amber-200"
      role="status"
      data-testid="billing-webhook-events-caveat">
      <span
        v-if="capped"
        data-testid="billing-webhook-events-capped">
        {{ t('web.admin.billing.webhookEvents.capped') }}
      </span>
      <span
        v-if="staleCount > 0"
        data-testid="billing-webhook-events-stale">
        {{ t('web.admin.billing.webhookEvents.stale', { count: staleCount }) }}
      </span>
    </div>

    <div
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <DataTable
        :columns="columns"
        :rows="events"
        row-key="event_id"
        :loading="loading"
        :empty-text="t('web.admin.billing.webhookEvents.empty')"
        testid="billing-webhook-events-table">
        <template #cell-eventId="{ row }">
          <span class="font-mono text-xs text-gray-900 tabular-nums dark:text-white">{{
            row.event_id
          }}</span>
        </template>
        <template #cell-type="{ row }">
          {{ row.event_type || '—' }}
        </template>
        <template #cell-status="{ row }">
          <span
            class="inline-flex items-center rounded px-2 py-0.5 text-xs font-medium"
            :class="statusClass(row.processing_status)">
            {{ row.processing_status || '—' }}
          </span>
        </template>
        <template #cell-received="{ row }">
          <span class="text-sm text-gray-500 tabular-nums dark:text-gray-400">{{
            timestamp(row.received_at)
          }}</span>
        </template>
        <template #cell-outcome="{ row }">
          {{ row.processing_outcome || '—' }}
        </template>
        <template #cell-actions="{ row }">
          <button
            type="button"
            class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-800"
            :data-testid="`billing-webhook-event-detail-${row.event_id}`"
            @click="openDetail(row)">
            {{ t('web.admin.billing.webhookEvents.viewDetail') }}
          </button>
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

    <DetailDrawer
      v-model:open="drawerOpen"
      :title="t('web.admin.billing.webhookEvents.detail.title')"
      :subtitle="selectedEvent?.event_id"
      testid="billing-webhook-event-detail-drawer"
      @close="closeDetail">
      <div
        v-if="detailLoading"
        class="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400"
        data-testid="billing-webhook-event-detail-loading">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4"
          class="animate-spin motion-reduce:animate-none" />
        {{ t('web.COMMON.loading') }}
      </div>
      <div
        v-else-if="detailNotFound"
        class="text-sm text-gray-600 dark:text-gray-300"
        data-testid="billing-webhook-event-detail-not-found">
        {{ t('web.admin.billing.webhookEvents.detail.notFound') }}
      </div>
      <div
        v-else-if="detailFailed"
        class="space-y-3"
        role="alert"
        data-testid="billing-webhook-event-detail-error">
        <p class="text-sm text-red-800 dark:text-red-200">
          {{ t('web.admin.billing.webhookEvents.detail.loadError') }}
        </p>
        <button
          type="button"
          class="rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
          @click="loadDetail().catch(() => {})">
          {{ t('web.admin.billing.retry') }}
        </button>
      </div>
      <dl
        v-else-if="detail"
        class="space-y-3 text-sm"
        data-testid="billing-webhook-event-detail-content">
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.billing.webhookEvents.columns.type') }}
          </dt>
          <dd class="mt-0.5 break-words text-gray-900 dark:text-white">
            {{ detail.event_type || '—' }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.billing.webhookEvents.columns.status') }}
          </dt>
          <dd class="mt-0.5 text-gray-900 dark:text-white">
            {{ detail.processing_status || '—' }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.billing.webhookEvents.columns.outcome') }}
          </dt>
          <dd class="mt-0.5 break-words text-gray-900 dark:text-white">
            {{ detail.processing_outcome || '—' }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.billing.webhookEvents.detail.received') }}
          </dt>
          <dd class="mt-0.5 text-gray-900 tabular-nums dark:text-white">
            {{ timestamp(detail.received_at) }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.billing.webhookEvents.detail.lastAttempt') }}
          </dt>
          <dd class="mt-0.5 text-gray-900 tabular-nums dark:text-white">
            {{ timestamp(detailMetadata?.last_attempt_at) }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.billing.webhookEvents.detail.processed') }}
          </dt>
          <dd class="mt-0.5 text-gray-900 tabular-nums dark:text-white">
            {{ timestamp(detail.processed_at) }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.billing.webhookEvents.detail.attempts') }}
          </dt>
          <dd class="mt-0.5 text-gray-900 tabular-nums dark:text-white">
            {{ detail.attempt_count ?? '—' }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.billing.webhookEvents.detail.mode') }}
          </dt>
          <dd class="mt-0.5 text-gray-900 dark:text-white">
            {{
              detailMetadata?.livemode == null
                ? '—'
                : detailMetadata.livemode
                  ? t('web.admin.billing.webhookEvents.detail.live')
                  : t('web.admin.billing.webhookEvents.detail.test')
            }}
          </dd>
        </div>
        <div>
          <dt class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.billing.webhookEvents.detail.apiVersion') }}
          </dt>
          <dd class="mt-0.5 text-gray-900 dark:text-white">
            {{ detailMetadata?.api_version || '—' }}
          </dd>
        </div>
      </dl>
    </DetailDrawer>
  </section>
</template>
