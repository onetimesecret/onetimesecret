<!-- src/apps/admin/views/AdminQueueDlq.vue -->

<script setup lang="ts">
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import {
    AdminConfirmDialog,
    DataTable,
    DetailDrawer,
    FilterBar,
    JsonViewer,
    KitPagination,
    StatCard,
  } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import { useAdminQueueDlq } from '@/apps/admin/stores/useAdminQueueDlq';
  import type {
    ColonelDlqSummary,
    ColonelDlqMessage,
  } from '@/schemas/api/account/responses/colonel-queue';
  import {
    colonelDlqMessagesResponseSchema,
    colonelDlqReplayResponseSchema,
    colonelDlqPurgeResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-queue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { gracefulParse } from '@/utils/schemaValidation';

  /**
   * Queue DLQ console (ticket #42) — a Phase-3 screen: a CLI-only power
   * (`bin/ots queue dlq …`) surfaced in the browser, built on the Slice-3 template
   * (no `src/apps/colonel/*` / `colonelInfoStore`). Sits beside the existing
   * queue-status widget / `GetQueueMetrics`, upgrading a read-only view into an
   * actionable one.
   *
   * - LIST: DataTable + FilterBar + KitPagination over the NEW {@link useAdminQueueDlq}
   *   store. `GET /api/colonel/queues/dlq` is a thin adapter over
   *   `Onetime::Operations::Dlq::List` (the fixed DLQ allowlist — bounded, #2211).
   * - INSPECT DRAWER: a row opens {@link DetailDrawer} loading
   *   `GET /api/colonel/queues/dlq/:queue` via {@link useResourceFetch}
   *   (`Dlq::Peek`) — a non-destructive peek of the dead-letter payloads, each
   *   inspectable via {@link JsonViewer}.
   * - GUARDED REPLAY (D4, low-ish risk): re-enqueues the DLQ back to its origin.
   *   Because replay can re-trigger side effects (emails, webhooks), it DEFAULTS
   *   to a dry-run: clicking Replay first POSTs `{dry_run:true}` to preview the
   *   in-scope `would_replay` count, then the live replay is an explicit second
   *   step behind {@link AdminConfirmDialog} (one-click, no token; the copy shows
   *   the previewed count). Audited SERVER-SIDE by `Dlq::Replay` only on the live
   *   run (the dry-run is a no-op that records nothing).
   * - GUARDED PURGE (D4, destructive): irreversible message loss, gated by
   *   {@link AdminConfirmDialog} typed-confirmation (retype the queue name) in
   *   danger mode with the count-in-scope shown; audited SERVER-SIDE by `Dlq::Purge`.
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  const store = useAdminQueueDlq();
  const { dlqs, pagination, connected, loading, error } = storeToRefs(store);

  // ---- List + filter --------------------------------------------------------

  const searchTerm = ref('');
  const hasActiveFilters = computed(() => searchTerm.value !== '');

  /** Strip the `dlq.` prefix for a friendlier display / confirm token. */
  function shortName(queue: string): string {
    return queue.replace(/^dlq\./, '');
  }

  /** Client-side filter over the (small, fixed) DLQ set. */
  const filteredDlqs = computed<ColonelDlqSummary[]>(() => {
    const needle = searchTerm.value.trim().toLowerCase();
    if (!needle) return dlqs.value;
    return dlqs.value.filter((d) => d.queue.toLowerCase().includes(needle));
  });

  const totalMessages = computed(() =>
    dlqs.value.reduce((sum, d) => sum + (d.messages ?? 0), 0)
  );

  const columns = computed<DataTableColumn<ColonelDlqSummary>[]>(() => [
    { key: 'queue', label: t('web.admin.queue.columns.queue') },
    { key: 'messages', label: t('web.admin.queue.columns.messages'), align: 'right' },
    { key: 'consumers', label: t('web.admin.queue.columns.consumers'), align: 'right' },
    { key: 'actions', label: t('web.admin.queue.columns.actions'), align: 'right' },
  ]);

  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(targetPage);
    } catch {
      // Network/HTTP failure is captured in `store.error`; the banner + retry
      // button below handle it. Swallow so it doesn't become unhandled.
    }
  }

  function onClear(): void {
    searchTerm.value = '';
  }

  function onPageChange(targetPage: number): void {
    fetchPage(targetPage);
  }

  function onPerPageChange(perPage: number): void {
    store.perPage = perPage;
    fetchPage(1);
  }

  // ---- Inspect drawer (peek) ------------------------------------------------

  const drawerOpen = ref(false);
  /** The row that opened the drawer — the source of the queue id. */
  const selectedDlq = ref<ColonelDlqSummary | null>(null);

  const detailUrl = (): string =>
    `/api/colonel/queues/dlq/${encodeURIComponent(selectedDlq.value?.queue ?? '')}`;

  const {
    data: detailData,
    loading: detailLoading,
    error: detailError,
    validationError: detailValidationError,
    load: loadDetail,
  } = useResourceFetch({
    url: detailUrl,
    schema: colonelDlqMessagesResponseSchema,
    context: 'ColonelDlqMessagesResponse',
  });

  const detailMessages = computed<ColonelDlqMessage[]>(
    () => detailData.value?.details?.messages ?? []
  );
  const detailRecord = computed(() => detailData.value?.record ?? null);
  const detailLoadFailed = computed(
    () => detailError.value !== null || detailValidationError.value !== null
  );

  function openDetail(row: ColonelDlqSummary): void {
    selectedDlq.value = row;
    drawerOpen.value = true;
    loadDetail().catch(() => {});
  }

  function closeDrawer(): void {
    drawerOpen.value = false;
    selectedDlq.value = null;
  }

  // ---- Guarded mutations (D4) ----------------------------------------------

  type ActionKey = 'replay' | 'purge';

  const dialogOpen = ref(false);
  const activeAction = ref<ActionKey | null>(null);
  /** Full queue name the action targets (request path). */
  const targetQueue = ref('');
  /** Message count in scope at request time (for the purge confirm copy). */
  const targetCount = ref(0);
  /**
   * In-scope count returned by the replay DRY-RUN preview (`would_replay`), shown
   * in the confirm copy before the live replay. Null until a preview has run.
   */
  const replayWouldReplay = ref<number | null>(null);

  const {
    loading: mutationLoading,
    error: mutationError,
    run: runMutation,
    reset: resetMutation,
  } = useAdminMutation(async () => {
    const queue = targetQueue.value;
    if (!queue) throw new Error('No queue selected');
    const path = `/api/colonel/queues/dlq/${encodeURIComponent(queue)}`;

    if (activeAction.value === 'replay') {
      // Explicit LIVE replay (the second, confirmed step after the dry-run
      // preview). `dry_run:false` re-publishes and is the audited mutation.
      const response = await $api.post(`${path}/replay`, { dry_run: false });
      // A 2xx means the replay ran server-side regardless of ack shape; the parse
      // keeps the contract a live tripwire without failing the action.
      gracefulParse(colonelDlqReplayResponseSchema, response.data, 'ColonelDlqReplayResponse');
    } else {
      const response = await $api.post(`${path}/purge`, {});
      gracefulParse(colonelDlqPurgeResponseSchema, response.data, 'ColonelDlqPurgeResponse');
    }
  });

  /**
   * Replay DRY-RUN preview (the safe first step). POSTs `{dry_run:true}` — a
   * server-side no-op that measures `would_replay` without republishing or
   * auditing — so the operator sees the in-scope count before committing.
   */
  const {
    loading: replayPreviewLoading,
    error: replayPreviewError,
    run: runReplayPreview,
    reset: resetReplayPreview,
  } = useAdminMutation(async (queue: string) => {
    replayWouldReplay.value = null;
    const path = `/api/colonel/queues/dlq/${encodeURIComponent(queue)}`;
    const response = await $api.post(`${path}/replay`, { dry_run: true });
    const parsed = gracefulParse(
      colonelDlqReplayResponseSchema,
      response.data,
      'ColonelDlqReplayResponse'
    );
    replayWouldReplay.value = parsed.ok ? (parsed.data.record?.would_replay ?? 0) : 0;
  });

  /** Purge is destructive → typed-confirmation (retype the short queue name). */
  const dialogConfig = computed(() => {
    const short = shortName(targetQueue.value);
    if (activeAction.value === 'purge') {
      return {
        title: t('web.admin.queue.purge.confirmTitle'),
        description: t('web.admin.queue.purge.confirmDescription', {
          queue: short,
          count: targetCount.value,
        }),
        confirmText: t('web.admin.queue.purge.button'),
        confirmToken: short,
        variant: 'danger' as const,
      };
    }
    return {
      title: t('web.admin.queue.replay.confirmTitle'),
      description: t('web.admin.queue.replay.confirmDescription', {
        queue: short,
        count: replayWouldReplay.value ?? 0,
      }),
      confirmText: t('web.admin.queue.replay.confirmLive'),
      confirmToken: undefined,
      variant: 'default' as const,
    };
  });

  async function requestReplay(row: ColonelDlqSummary): Promise<void> {
    activeAction.value = 'replay';
    targetQueue.value = row.queue;
    targetCount.value = row.messages ?? 0;
    replayWouldReplay.value = null;
    resetMutation();
    resetReplayPreview();
    // Safe first step: dry-run preview. Only open the live-replay confirm once
    // we know the in-scope count; a preview failure surfaces its own banner.
    const ok = await runReplayPreview(row.queue);
    if (ok) dialogOpen.value = true;
  }

  function requestPurge(row: ColonelDlqSummary): void {
    activeAction.value = 'purge';
    targetQueue.value = row.queue;
    targetCount.value = row.messages ?? 0;
    resetMutation();
    dialogOpen.value = true;
  }

  async function onConfirm(): Promise<void> {
    const action = activeAction.value;
    if (!action) return;

    const ok = await runMutation();
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    dialogOpen.value = false;
    const short = shortName(targetQueue.value);

    if (action === 'replay') {
      notifications.show(t('web.admin.queue.replay.success', { queue: short }), 'success');
    } else {
      notifications.show(t('web.admin.queue.purge.success', { queue: short }), 'success');
    }

    // Refresh the drawer (if the acted-on queue is open) and the list — depths
    // changed.
    if (drawerOpen.value && selectedDlq.value?.queue === targetQueue.value) {
      loadDetail().catch(() => {});
    }
    activeAction.value = null;
    replayWouldReplay.value = null;
    await fetchPage(pagination.value?.page ?? 1);
  }

  function onCancel(): void {
    dialogOpen.value = false;
    activeAction.value = null;
    replayWouldReplay.value = null;
    resetMutation();
    resetReplayPreview();
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <div class="mb-6">
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.queue.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.queue.description') }}
      </p>
    </div>

    <!-- Network/HTTP error banner (validation mismatches degrade to empty). -->
    <div
      v-if="error"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="dlq-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.queue.list.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="fetchPage(1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.queue.list.retry') }}
      </button>
    </div>

    <!-- Replay dry-run preview failure (blocks opening the live-replay confirm). -->
    <div
      v-if="replayPreviewError"
      class="mb-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800 dark:border-red-900/50 dark:bg-red-900/20 dark:text-red-200"
      role="alert"
      data-testid="dlq-replay-preview-error">
      {{ replayPreviewError }}
    </div>

    <!-- Broker-not-connected notice -->
    <div
      v-if="connected === false && !error"
      class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800 dark:border-amber-900/50 dark:bg-amber-900/20 dark:text-amber-200"
      role="status"
      data-testid="dlq-disconnected">
      {{ t('web.admin.queue.list.disconnected') }}
    </div>

    <!-- Total in-scope -->
    <div class="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2">
      <StatCard
        :label="t('web.admin.queue.stats.total')"
        :value="totalMessages"
        icon="inbox-arrow-down"
        testid="stat-total" />
      <StatCard
        :label="t('web.admin.queue.stats.queues')"
        :value="dlqs.length"
        icon="rectangle-stack"
        testid="stat-queues" />
    </div>

    <!-- Filter -->
    <div class="mb-4">
      <FilterBar
        v-model:search="searchTerm"
        :search-placeholder="t('web.admin.queue.search.placeholder')"
        :has-active-filters="hasActiveFilters"
        testid="dlq-filterbar"
        @clear="onClear" />
    </div>

    <!-- Table -->
    <div
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <DataTable
        :columns="columns"
        :rows="filteredDlqs"
        row-key="queue"
        :loading="loading"
        :empty-text="t('web.admin.queue.list.empty')"
        clickable-rows
        testid="dlq-table"
        @row-click="openDetail">
        <template #cell-queue="{ row }">
          <span class="font-mono text-gray-900 dark:text-white">{{ shortName(row.queue) }}</span>
          <span
            v-if="row.error"
            class="ml-2 rounded bg-gray-100 px-1.5 py-0.5 text-xs text-gray-500 dark:bg-gray-800 dark:text-gray-400">
            {{ row.error }}
          </span>
        </template>

        <template #cell-messages="{ row }">
          <span
            :class="[
              'font-mono font-semibold',
              row.messages > 0
                ? 'text-red-600 dark:text-red-400'
                : 'text-gray-400 dark:text-gray-600',
            ]"
            >{{ row.messages }}</span
          >
        </template>

        <template #cell-consumers="{ row }">
          <span class="font-mono text-xs text-gray-500 dark:text-gray-400">{{
            row.consumers ?? '—'
          }}</span>
        </template>

        <template #cell-actions="{ row }">
          <div class="flex items-center justify-end gap-3">
            <button
              type="button"
              :data-testid="`replay-${shortName(row.queue)}`"
              :disabled="row.messages === 0 || replayPreviewLoading"
              class="text-sm font-medium text-brand-600 hover:text-brand-800 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-40 dark:text-brand-400 dark:hover:text-brand-300"
              @click.stop="requestReplay(row)">
              {{ t('web.admin.queue.replay.button') }}
            </button>
            <button
              type="button"
              :data-testid="`purge-${shortName(row.queue)}`"
              :disabled="row.messages === 0"
              class="text-sm font-medium text-red-600 hover:text-red-800 focus:outline-none focus:ring-2 focus:ring-red-500 disabled:cursor-not-allowed disabled:opacity-40 dark:text-red-400 dark:hover:text-red-300"
              @click.stop="requestPurge(row)">
              {{ t('web.admin.queue.purge.button') }}
            </button>
          </div>
        </template>
      </DataTable>
    </div>

    <!-- Pagination -->
    <KitPagination
      v-if="pagination"
      :pagination="pagination"
      :loading="loading"
      class="mt-4"
      @update:page="onPageChange"
      @update:per-page="onPerPageChange" />

    <!-- Detail drawer (peek) -->
    <DetailDrawer
      v-model:open="drawerOpen"
      :title="selectedDlq ? t('web.admin.queue.drawer.title', { queue: shortName(selectedDlq.queue) }) : ''"
      :subtitle="
        detailRecord
          ? t('web.admin.queue.drawer.subtitle', {
              total: detailRecord.total_messages,
              showing: detailRecord.showing,
            })
          : undefined
      "
      width-class="max-w-2xl"
      testid="dlq-drawer"
      @close="closeDrawer">
      <!-- Loading -->
      <div
        v-if="detailLoading && detailMessages.length === 0"
        class="flex items-center justify-center py-16 text-gray-500 dark:text-gray-400"
        data-testid="dlq-drawer-loading">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="6"
          class="animate-spin motion-reduce:animate-none" />
        <span class="ml-3 text-sm">{{ t('web.COMMON.loading') }}</span>
      </div>

      <!-- Load error -->
      <div
        v-else-if="detailLoadFailed"
        class="px-2 py-12 text-center"
        role="alert"
        data-testid="dlq-drawer-error">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          size="8"
          class="mx-auto text-red-500 dark:text-red-400" />
        <p class="mt-3 text-sm text-red-800 dark:text-red-200">
          {{ t('web.admin.queue.drawer.loadError') }}
        </p>
        <button
          type="button"
          class="mt-4 inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
          @click="loadDetail().catch(() => {})">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            size="4" />
          {{ t('web.admin.queue.drawer.retry') }}
        </button>
      </div>

      <!-- Empty -->
      <div
        v-else-if="detailMessages.length === 0"
        class="px-2 py-12 text-center"
        data-testid="dlq-drawer-empty">
        <OIcon
          collection="heroicons"
          name="inbox-arrow-down"
          size="8"
          class="mx-auto text-gray-400 dark:text-gray-600" />
        <p class="mt-3 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.queue.drawer.empty') }}
        </p>
      </div>

      <!-- Messages -->
      <div
        v-else
        class="space-y-4"
        data-testid="dlq-drawer-content">
        <article
          v-for="(msg, idx) in detailMessages"
          :key="msg.delivery_tag ?? msg.message_id ?? idx"
          class="rounded-lg border border-gray-200 p-4 dark:border-gray-800"
          :data-testid="`dlq-message-${idx}`">
          <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
            <span class="font-mono text-xs text-gray-500 dark:text-gray-400">
              {{ msg.message_id || t('web.admin.queue.message.noId') }}
            </span>
            <span class="text-xs text-gray-400 dark:text-gray-500">{{ msg.age }}</span>
          </div>
          <dl class="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
            <div>
              <dt class="text-gray-500 dark:text-gray-400">
                {{ t('web.admin.queue.message.originalQueue') }}
              </dt>
              <dd class="font-mono text-gray-900 dark:text-gray-100">
                {{ msg.original_queue || '—' }}
              </dd>
            </div>
            <div>
              <dt class="text-gray-500 dark:text-gray-400">
                {{ t('web.admin.queue.message.deathReason') }}
              </dt>
              <dd class="font-mono text-gray-900 dark:text-gray-100">
                {{ msg.death_reason || '—' }}
              </dd>
            </div>
          </dl>
          <p
            v-if="msg.error"
            class="mt-2 break-words rounded bg-red-50 px-2 py-1 font-mono text-xs text-red-700 dark:bg-red-900/20 dark:text-red-300">
            {{ msg.error }}
          </p>
          <div class="mt-3">
            <JsonViewer
              :data="msg"
              :expand-depth="0"
              :testid="`dlq-message-json-${idx}`" />
          </div>
        </article>
      </div>

      <!-- Footer: guarded replay + purge -->
      <template #footer>
        <div class="flex w-full gap-3">
          <button
            type="button"
            data-testid="dlq-drawer-replay"
            :disabled="!selectedDlq || (detailRecord?.total_messages ?? 0) === 0 || replayPreviewLoading"
            class="inline-flex flex-1 items-center justify-center gap-1 rounded-md border border-brand-300 px-3 py-2 text-sm font-semibold text-brand-700 hover:bg-brand-50 focus:outline-none focus:ring-2 focus:ring-brand-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-brand-800 dark:text-brand-300 dark:hover:bg-brand-900/30"
            @click="selectedDlq && requestReplay(selectedDlq)">
            <OIcon
              collection="heroicons"
              name="arrow-uturn-left"
              size="4" />
            {{ t('web.admin.queue.replay.button') }}
          </button>
          <button
            type="button"
            data-testid="dlq-drawer-purge"
            :disabled="!selectedDlq || (detailRecord?.total_messages ?? 0) === 0"
            class="inline-flex flex-1 items-center justify-center gap-1 rounded-md border border-red-300 px-3 py-2 text-sm font-semibold text-red-700 hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 disabled:cursor-not-allowed disabled:opacity-50 dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/30"
            @click="selectedDlq && requestPurge(selectedDlq)">
            <OIcon
              collection="heroicons"
              name="trash"
              size="4" />
            {{ t('web.admin.queue.purge.button') }}
          </button>
        </div>
      </template>
    </DetailDrawer>

    <!-- Shared guarded-action dialog: one-click replay / typed-confirmation purge. -->
    <AdminConfirmDialog
      v-model:open="dialogOpen"
      :title="dialogConfig.title"
      :description="dialogConfig.description"
      :confirm-token="dialogConfig.confirmToken"
      :variant="dialogConfig.variant"
      :confirm-text="dialogConfig.confirmText"
      :loading="mutationLoading"
      :error="mutationError"
      @confirm="onConfirm"
      @cancel="onCancel" />
  </div>
</template>
