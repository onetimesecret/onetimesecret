<!-- src/apps/admin/views/AdminAuditLog.vue -->

<script setup lang="ts">

  import { DataTable, FilterBar, KitPagination } from '@/apps/admin/components/kit';
  import type { DataTableColumn, FilterConfig } from '@/apps/admin/components/kit';
  import { useAdminAuditLog } from '@/apps/admin/stores/useAdminAuditLog';
  import type { ColonelAuditEvent } from '@/schemas/api/internal/responses/colonel-audit';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Audit Log screen (observability lane) — the playback for the flight
   * recorder: every mutating admin op writes an AdminAuditEvent; this screen
   * reads them newest-first over `GET /api/colonel/audit` via the NEW
   * {@link useAdminAuditLog} store (no `src/apps/colonel/*` / `colonelInfoStore`).
   *
   * - LIST: DataTable + KitPagination, timestamp/actor/action/target/result/detail.
   * - FILTERS: the FilterBar search box drives the server-side `actor` filter
   *   (case-insensitive substring, debounced like the sessions search) and a
   *   category `<select>` drives the `verb` filter (prefix match server-side).
   * - READ-ONLY: viewing the log never writes an audit event (CONTRACT 4), so
   *   there are no mutations — and deliberately no way to edit or delete
   *   entries from the UI.
   */
  const { t } = useI18n();

  const store = useAdminAuditLog();
  const { events, pagination, loading, error } = storeToRefs(store);

  // ---- Filters ---------------------------------------------------------------

  const actorTerm = ref('');
  const activeActor = ref('');
  const verbCategory = ref('');
  const hasActiveFilters = computed(() => actorTerm.value !== '' || verbCategory.value !== '');

  /**
   * Action categories = the dotted-verb prefixes the ops layer writes today
   * (customer.set_role, session.delete, queue.dlq.replay, …). The server
   * treats the value as a prefix, so an uncategorised future verb still shows
   * under "All" — this list only feeds the convenience select.
   */
  const VERB_CATEGORIES = [
    'customer',
    'session',
    'domain',
    'organization',
    'banner',
    'queue',
    'email',
    'ratelimit',
    'ip',
  ] as const;

  const filters = computed<FilterConfig[]>(() => [
    {
      key: 'verb',
      label: t('web.admin.audit.filters.actionLabel'),
      value: verbCategory.value,
      allLabel: t('web.admin.audit.filters.allActions'),
      options: VERB_CATEGORIES.map((category) => ({
        value: category,
        label: t(`web.admin.audit.categories.${category}`),
      })),
    },
  ]);

  // ---- List ------------------------------------------------------------------

  const columns = computed<DataTableColumn<ColonelAuditEvent>[]>(() => [
    { key: 'created', label: t('web.admin.audit.columns.timestamp') },
    { key: 'actor', label: t('web.admin.audit.columns.actor') },
    { key: 'verb', label: t('web.admin.audit.columns.action') },
    { key: 'target', label: t('web.admin.audit.columns.target') },
    { key: 'result', label: t('web.admin.audit.columns.result'), align: 'center' },
    { key: 'detail', label: t('web.admin.audit.columns.detail') },
  ]);

  /** Fetch one server page with the active filters. Errors surface via the store. */
  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(targetPage, {
        actor: activeActor.value || undefined,
        verb: verbCategory.value || undefined,
      });
    } catch {
      // Network/HTTP failure is captured in `store.error`; the banner + retry
      // button below handle it. Swallow so it doesn't become unhandled.
    }
  }

  // Debounce actor input so we issue one request per pause, not per keystroke.
  let actorTimer: ReturnType<typeof setTimeout> | null = null;
  watch(actorTerm, (value) => {
    if (actorTimer) clearTimeout(actorTimer);
    actorTimer = setTimeout(() => {
      activeActor.value = value.trim();
      fetchPage(1);
    }, 300);
  });
  onBeforeUnmount(() => {
    if (actorTimer) clearTimeout(actorTimer);
  });

  function onFilterChange(key: string, value: string): void {
    if (key !== 'verb') return;
    verbCategory.value = value;
    fetchPage(1);
  }

  function onClear(): void {
    actorTerm.value = '';
    activeActor.value = '';
    verbCategory.value = '';
    fetchPage(1);
  }

  function onPageChange(targetPage: number): void {
    fetchPage(targetPage);
  }

  function onPerPageChange(perPage: number): void {
    store.perPage = perPage;
    fetchPage(1);
  }

  // ---- Cell rendering ---------------------------------------------------------

  /** Compact single-line rendering of the free-form redacted detail payload. */
  function detailLabel(detail: unknown): string {
    if (detail === null || detail === undefined) return '—';
    const text = typeof detail === 'string' ? detail : JSON.stringify(detail);
    return text.length > 80 ? `${text.slice(0, 80)}…` : text;
  }

  /** Full detail for the cell title (hover) — never truncated. */
  function detailTitle(detail: unknown): string | undefined {
    if (detail === null || detail === undefined) return undefined;
    return typeof detail === 'string' ? detail : JSON.stringify(detail, null, 2);
  }

  function resultBadgeClass(result: string): string {
    return result === 'success'
      ? 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-200'
      : 'bg-red-100 text-red-800 dark:bg-red-900/40 dark:text-red-200';
  }

  onMounted(() => fetchPage(1));
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <header class="mb-6 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        {{ t('web.admin.audit.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.audit.description') }}
      </p>
    </header>

    <!-- Network/HTTP error banner (validation mismatches degrade to empty). -->
    <div
      v-if="error"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="audit-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.audit.list.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="fetchPage(1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.audit.list.retry') }}
      </button>
    </div>

    <!-- Filters: actor substring (search box) + action category (select) -->
    <div class="mb-4">
      <FilterBar
        v-model:search="actorTerm"
        :search-placeholder="t('web.admin.audit.filters.actorPlaceholder')"
        :filters="filters"
        :has-active-filters="hasActiveFilters"
        testid="audit-filterbar"
        @filter-change="onFilterChange"
        @clear="onClear" />
    </div>

    <!-- Table -->
    <div
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <DataTable
        :columns="columns"
        :rows="events"
        row-key="id"
        :loading="loading"
        :empty-text="t('web.admin.audit.list.empty')"
        testid="audit-table">
        <template #cell-created="{ row }">
          <span class="whitespace-nowrap text-gray-900 tabular-nums dark:text-white">
            {{ formatDisplayDateTime(row.created) }}
          </span>
        </template>

        <template #cell-actor="{ row }">
          <span class="font-mono text-xs text-gray-900 dark:text-white">{{ row.actor }}</span>
        </template>

        <template #cell-verb="{ row }">
          <span class="font-mono text-xs text-gray-700 dark:text-gray-300">{{ row.verb }}</span>
        </template>

        <template #cell-target="{ row }">
          <span class="font-mono text-xs text-gray-500 dark:text-gray-400">{{ row.target }}</span>
        </template>

        <template #cell-result="{ row }">
          <span
            class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium"
            :class="resultBadgeClass(row.result)">
            {{
              row.result === 'success'
                ? t('web.admin.audit.result.success')
                : row.result === 'failure'
                  ? t('web.admin.audit.result.failure')
                  : row.result
            }}
          </span>
        </template>

        <template #cell-detail="{ row }">
          <span
            class="block max-w-xs truncate font-mono text-xs text-gray-500 dark:text-gray-400"
            :title="detailTitle(row.detail)">
            {{ detailLabel(row.detail) }}
          </span>
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
  </div>
</template>
