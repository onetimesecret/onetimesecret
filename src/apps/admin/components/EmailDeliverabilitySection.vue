<!-- src/apps/admin/components/EmailDeliverabilitySection.vue -->

<script setup lang="ts">
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import {
    AdminConfirmDialog,
    DataTable,
    KitPagination,
    StatCard,
  } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { usePaginatedFetch, type PageMeta } from '@/apps/admin/composables/usePaginatedFetch';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import type {
    ColonelDeliverabilityEvent,
    ColonelEmailSuppression,
  } from '@/schemas/api/internal/responses/colonel-deliverability';
  import {
    colonelEmailDeliverabilityEventsResponseSchema,
    colonelEmailDeliverabilityResponseSchema,
    colonelEmailSuppressionRemoveResponseSchema,
    colonelEmailSuppressionsResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-deliverability';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { gracefulParse } from '@/utils/schemaValidation';

  /**
   * Deliverability section for the Email Tools screen — the RECEIVING side of
   * email. The screen's other sections prove mail goes OUT (template preview,
   * test send); this one shows what comes BACK: bounce/complaint counts, the
   * suppression list the outbound guard skips, and the raw event feed — the
   * data that diagnoses a sender-reputation problem.
   *
   * Three sub-blocks, all under the `emailtools.deliverability` namespace:
   *  - SUMMARY TILES (read-only): suppressed total, bounces/complaints inside
   *    the server's recent window, and sends the suppression guard skipped.
   *  - SUPPRESSION LIST: newest-first pages plus an EXACT-address lookup (the
   *    store is keyed by address — a substring search would imply a capability
   *    the endpoint lacks). Removal is GUARDED (one-click confirm, the unban
   *    idiom): it re-enables sending to an address that bounced or complained,
   *    and is audited SERVER-SIDE by the op (CONTRACT 4).
   *  - RECENT EVENTS (read-only): the newest slice of the bounce/complaint
   *    feed. Its empty state explains how feedback gets here: an operator
   *    relay POSTs ESP records to the colonel-authenticated ingest endpoint
   *    (no public webhook, by design).
   *
   * Every mutation goes through {@link useAdminMutation}; nothing here logs.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const SUMMARY_URL = '/api/colonel/email/deliverability';
  const SUPPRESSIONS_URL = '/api/colonel/email/deliverability/suppressions';
  const EVENTS_URL = '/api/colonel/email/deliverability/events';

  /** The "recent" feed shows one newest-first slice (the API also paginates). */
  const EVENTS_LIMIT = 20;

  // ---- Summary tiles ---------------------------------------------------------

  const {
    data: summaryData,
    loading: summaryLoading,
    error: summaryError,
    load: loadSummary,
  } = useResourceFetch({
    url: SUMMARY_URL,
    schema: colonelEmailDeliverabilityResponseSchema,
    context: 'ColonelEmailDeliverabilityResponse',
  });

  const counts = computed(() => summaryData.value?.details?.counts ?? null);
  const windowDays = computed(() => summaryData.value?.details?.window_days ?? 7);

  function reloadSummary(): void {
    loadSummary().catch(() => {}); // summaryError drives the inline alert
  }

  // ---- Suppression list (paginated + exact-address lookup) -------------------

  const suppressions = ref<ColonelEmailSuppression[]>([]);
  const suppressionsMeta = ref<PageMeta | null>(null);
  const searchTerm = ref('');
  /** The lookup actually applied to the current rows (submitted, not typed). */
  const activeSearch = ref('');

  const {
    loading: suppressionsLoading,
    error: suppressionsError,
    perPage: suppressionsPerPage,
    fetchPage: fetchSuppressionsPage,
  } = usePaginatedFetch({
    url: SUPPRESSIONS_URL,
    schema: colonelEmailSuppressionsResponseSchema,
    context: 'ColonelEmailSuppressionsResponse',
    select: (data) => ({
      items: data.details?.suppressions ?? [],
      pagination: data.details?.pagination ?? null,
    }),
    perPage: 25,
  });

  async function fetchSuppressions(targetPage = 1): Promise<void> {
    try {
      const result = await fetchSuppressionsPage(
        targetPage,
        activeSearch.value ? { search: activeSearch.value } : undefined
      );
      if (result) {
        suppressions.value = result.items;
        suppressionsMeta.value = result.pagination;
      } else {
        // Schema mismatch: degrade to empty (gracefulParse already reported).
        suppressions.value = [];
        suppressionsMeta.value = null;
      }
    } catch {
      // suppressionsError drives the banner; keep stale rows off the screen.
      suppressions.value = [];
      suppressionsMeta.value = null;
    }
  }

  function onSearchSubmit(): void {
    activeSearch.value = searchTerm.value.trim();
    fetchSuppressions(1);
  }

  function onSearchClear(): void {
    searchTerm.value = '';
    activeSearch.value = '';
    fetchSuppressions(1);
  }

  function onSuppressionsPerPage(perPage: number): void {
    suppressionsPerPage.value = perPage;
    fetchSuppressions(1);
  }

  const suppressionColumns = computed<DataTableColumn<ColonelEmailSuppression>[]>(() => [
    { key: 'address', label: t('web.admin.emailtools.deliverability.suppressions.columns.address') },
    { key: 'reason', label: t('web.admin.emailtools.deliverability.suppressions.columns.reason') },
    { key: 'source', label: t('web.admin.emailtools.deliverability.suppressions.columns.source') },
    { key: 'created', label: t('web.admin.emailtools.deliverability.suppressions.columns.added') },
    {
      key: 'actions',
      label: t('web.admin.emailtools.deliverability.suppressions.columns.actions'),
      align: 'right',
    },
  ]);

  const suppressionsEmptyText = computed(() =>
    activeSearch.value
      ? t('web.admin.emailtools.deliverability.suppressions.emptySearch', {
          address: activeSearch.value,
        })
      : t('web.admin.emailtools.deliverability.suppressions.empty')
  );

  // ---- Guarded remove (one-click confirm — the unban idiom) ------------------

  const removeDialogOpen = ref(false);
  const removeTarget = ref('');

  const {
    loading: removeLoading,
    error: removeError,
    run: runRemove,
    reset: resetRemove,
  } = useAdminMutation(async () => {
    const response = await $api.delete(
      `${SUPPRESSIONS_URL}/${encodeURIComponent(removeTarget.value)}`
    );
    // 2xx means the suppression was removed server-side regardless of ack
    // shape; the parse keeps the contract a live tripwire, never fatal.
    gracefulParse(
      colonelEmailSuppressionRemoveResponseSchema,
      response.data,
      'ColonelEmailSuppressionRemoveResponse'
    );
  });

  function requestRemove(address: string): void {
    removeTarget.value = address;
    resetRemove();
    removeDialogOpen.value = true;
  }

  async function onRemoveConfirm(): Promise<void> {
    const ok = await runRemove();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    removeDialogOpen.value = false;
    notifications.show(
      t('web.admin.emailtools.deliverability.suppressions.remove.success', {
        address: removeTarget.value,
      }),
      'success'
    );
    // The list AND the suppressed-total tile both changed.
    fetchSuppressions(suppressionsMeta.value?.page ?? 1);
    reloadSummary();
  }

  function onRemoveCancel(): void {
    removeDialogOpen.value = false;
    resetRemove();
  }

  // ---- Recent events feed -----------------------------------------------------

  const {
    data: eventsData,
    loading: eventsLoading,
    error: eventsError,
    load: loadEvents,
  } = useResourceFetch({
    url: EVENTS_URL,
    schema: colonelEmailDeliverabilityEventsResponseSchema,
    context: 'ColonelEmailDeliverabilityEventsResponse',
  });

  const events = computed<ColonelDeliverabilityEvent[]>(
    () => eventsData.value?.details?.events ?? []
  );

  function reloadEvents(): void {
    loadEvents({ page: 1, per_page: EVENTS_LIMIT }).catch(() => {}); // eventsError drives the banner
  }

  const eventColumns = computed<DataTableColumn<ColonelDeliverabilityEvent>[]>(() => [
    { key: 'created', label: t('web.admin.emailtools.deliverability.events.columns.time') },
    { key: 'kind', label: t('web.admin.emailtools.deliverability.events.columns.kind') },
    { key: 'address', label: t('web.admin.emailtools.deliverability.events.columns.address') },
    { key: 'source', label: t('web.admin.emailtools.deliverability.events.columns.source') },
    { key: 'reason', label: t('web.admin.emailtools.deliverability.events.columns.reason') },
  ]);

  /**
   * Badge styling per kind/reason: complaints are the harsher signal (red),
   * bounces warn (amber), manual imports are neutral (gray).
   */
  function kindClass(kind: string): string {
    if (kind === 'complaint') {
      return 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-300';
    }
    if (kind === 'bounce') {
      return 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300';
    }
    return 'bg-gray-100 text-gray-700 dark:bg-gray-800 dark:text-gray-300';
  }

  function kindLabel(kind: string): string {
    return kind === 'complaint'
      ? t('web.admin.emailtools.deliverability.events.kinds.complaint')
      : t('web.admin.emailtools.deliverability.events.kinds.bounce');
  }

  onMounted(() => {
    reloadSummary();
    fetchSuppressions(1);
    reloadEvents();
  });
</script>

<template>
  <section
    class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-800 dark:bg-gray-900"
    data-testid="deliverability-section">
    <h3 class="mb-3 text-lg font-semibold text-gray-900 dark:text-white">
      {{ t('web.admin.emailtools.deliverability.title') }}
    </h3>
    <p class="mb-4 text-sm text-gray-500 dark:text-gray-400">
      {{ t('web.admin.emailtools.deliverability.description') }}
    </p>

    <!-- Summary error (tiles degrade to skeletons/dashes, alert offers retry) -->
    <div
      v-if="summaryError"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="deliverability-summary-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.emailtools.deliverability.summary.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="reloadSummary">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.emailtools.deliverability.retry') }}
      </button>
    </div>

    <!-- Summary tiles -->
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
      <StatCard
        :label="t('web.admin.emailtools.deliverability.tiles.suppressed')"
        :value="counts?.suppressed_total ?? '—'"
        icon="no-symbol"
        :loading="summaryLoading"
        testid="deliverability-stat-suppressed" />
      <StatCard
        :label="t('web.admin.emailtools.deliverability.tiles.bounces', { days: windowDays })"
        :value="counts?.recent_bounces ?? '—'"
        icon="arrow-uturn-left"
        :loading="summaryLoading"
        testid="deliverability-stat-bounces" />
      <StatCard
        :label="t('web.admin.emailtools.deliverability.tiles.complaints', { days: windowDays })"
        :value="counts?.recent_complaints ?? '—'"
        icon="hand-raised"
        :loading="summaryLoading"
        testid="deliverability-stat-complaints" />
      <StatCard
        :label="t('web.admin.emailtools.deliverability.tiles.skipped')"
        :value="counts?.sends_skipped ?? '—'"
        icon="shield-check"
        :loading="summaryLoading"
        testid="deliverability-stat-skipped" />
    </div>

    <!-- ===== Suppression list ============================================ -->
    <div class="mt-8 border-t border-gray-100 pt-6 dark:border-gray-800">
      <h4 class="text-base font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.deliverability.suppressions.title') }}
      </h4>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.deliverability.suppressions.description') }}
      </p>

      <!-- Exact-address lookup (submitted, not live — the endpoint is keyed) -->
      <form
        class="mt-4 flex flex-wrap items-end gap-3"
        @submit.prevent="onSearchSubmit">
        <div class="min-w-[18rem] flex-1">
          <label
            for="deliverability-search"
            class="mb-1 block text-xs font-medium text-gray-500 dark:text-gray-400">
            {{ t('web.admin.emailtools.deliverability.suppressions.searchLabel') }}
          </label>
          <input
            id="deliverability-search"
            v-model="searchTerm"
            type="text"
            data-testid="deliverability-search-input"
            :placeholder="t('web.admin.emailtools.deliverability.suppressions.searchPlaceholder')"
            class="w-full rounded-md border border-gray-300 px-3 py-2 font-mono text-sm text-gray-900 focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <button
          type="submit"
          data-testid="deliverability-search-submit"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700">
          <OIcon
            collection="heroicons"
            name="magnifying-glass"
            size="4" />
          {{ t('web.admin.emailtools.deliverability.suppressions.searchButton') }}
        </button>
        <button
          v-if="activeSearch"
          type="button"
          data-testid="deliverability-search-clear"
          class="rounded-md px-3 py-2 text-sm font-medium text-gray-500 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:text-gray-400 dark:hover:text-gray-200"
          @click="onSearchClear">
          {{ t('web.admin.emailtools.deliverability.suppressions.clearButton') }}
        </button>
      </form>

      <p
        v-if="suppressionsError"
        class="mt-3 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="deliverability-suppressions-error">
        {{ t('web.admin.emailtools.deliverability.suppressions.loadError') }}
      </p>

      <div class="mt-4">
        <DataTable
          :columns="suppressionColumns"
          :rows="suppressions"
          row-key="address"
          :loading="suppressionsLoading"
          :empty-text="suppressionsEmptyText"
          testid="deliverability-suppressions-table">
          <template #cell-address="{ row }">
            <span class="font-mono text-sm text-gray-900 dark:text-gray-100">{{ row.address }}</span>
          </template>
          <template #cell-reason="{ row }">
            <span
              class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
              :class="kindClass(row.reason)">
              {{ row.reason }}
            </span>
          </template>
          <template #cell-source="{ row }">
            <span class="text-sm text-gray-500 dark:text-gray-400">{{ row.source || '—' }}</span>
          </template>
          <template #cell-created="{ row }">
            <span class="text-sm text-gray-500 dark:text-gray-400">{{ formatDisplayDateTime(row.created) }}</span>
          </template>
          <template #cell-actions="{ row }">
            <button
              type="button"
              :data-testid="`deliverability-remove-${row.address}`"
              class="rounded px-2 py-1 text-sm font-medium text-red-600 hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 dark:text-red-400 dark:hover:bg-red-900/30"
              @click="requestRemove(row.address)">
              {{ t('web.admin.emailtools.deliverability.suppressions.remove.button') }}
            </button>
          </template>
        </DataTable>

        <KitPagination
          v-if="suppressionsMeta && suppressionsMeta.total_pages > 1"
          :pagination="suppressionsMeta"
          :loading="suppressionsLoading"
          @update:page="fetchSuppressions"
          @update:per-page="onSuppressionsPerPage" />
      </div>
    </div>

    <!-- ===== Recent events feed ========================================== -->
    <div class="mt-8 border-t border-gray-100 pt-6 dark:border-gray-800">
      <h4 class="text-base font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.emailtools.deliverability.events.title') }}
      </h4>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.emailtools.deliverability.events.description') }}
      </p>

      <p
        v-if="eventsError"
        class="mt-3 text-sm text-red-700 dark:text-red-300"
        role="alert"
        data-testid="deliverability-events-error">
        {{ t('web.admin.emailtools.deliverability.events.loadError') }}
      </p>

      <div class="mt-4">
        <DataTable
          :columns="eventColumns"
          :rows="events"
          row-key="id"
          :loading="eventsLoading"
          :empty-text="t('web.admin.emailtools.deliverability.events.empty')"
          testid="deliverability-events-table">
          <template #cell-created="{ row }">
            <span class="text-sm text-gray-500 dark:text-gray-400">{{ formatDisplayDateTime(row.created) }}</span>
          </template>
          <template #cell-kind="{ row }">
            <span
              class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
              :class="kindClass(row.kind)">
              {{ kindLabel(row.kind) }}
            </span>
          </template>
          <template #cell-address="{ row }">
            <span class="font-mono text-sm text-gray-900 dark:text-gray-100">{{ row.address }}</span>
          </template>
          <template #cell-source="{ row }">
            <span class="text-sm text-gray-500 dark:text-gray-400">{{ row.source || '—' }}</span>
          </template>
          <template #cell-reason="{ row }">
            <span class="text-sm text-gray-500 dark:text-gray-400">{{ row.reason || '—' }}</span>
          </template>
        </DataTable>
      </div>
    </div>

    <!-- Suppression removal: one-click confirm (the unban idiom). Removing a
         suppression re-enables sending to a known-bad address, so the dialog
         copy says exactly that; the op audits server-side (CONTRACT 4). -->
    <AdminConfirmDialog
      v-model:open="removeDialogOpen"
      :title="t('web.admin.emailtools.deliverability.suppressions.remove.confirmTitle')"
      :description="
        t('web.admin.emailtools.deliverability.suppressions.remove.confirmDescription', {
          address: removeTarget,
        })
      "
      :confirm-token="undefined"
      variant="danger"
      :confirm-text="t('web.admin.emailtools.deliverability.suppressions.remove.button')"
      :loading="removeLoading"
      :error="removeError"
      @confirm="onRemoveConfirm"
      @cancel="onRemoveCancel" />
  </section>
</template>
