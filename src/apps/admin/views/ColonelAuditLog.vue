<!-- src/apps/admin/views/ColonelAuditLog.vue -->

<script setup lang="ts">

  import { DataTable, FilterBar, KitPagination } from '@/apps/admin/components/kit';
  import type { DataTableColumn, FilterConfig } from '@/apps/admin/components/kit';
  import { useColonelAuditLog } from '@/apps/admin/stores/useColonelAuditLog';
  import type { ColonelAuditEvent } from '@/schemas/api/internal/responses/colonel-audit';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { formatDisplayDateTime } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Audit Log screen (observability lane) — the playback for the flight
   * recorder: every mutating admin op writes an ColonelAuditEvent; this screen
   * reads them newest-first over `GET /api/colonel/audit` via the NEW
   * {@link useColonelAuditLog} store (no `src/apps/colonel/*` / `colonelInfoStore`).
   *
   * The feed merges the model's three trails — operator mutations, anonymous
   * security telemetry, and (since #4335) authenticated observations: curated
   * sensitive reads and dry-run previews. Rows carry a `trail` field naming the
   * source; the table does not render a column for it (an operator filters by
   * ACTION, which is the question they actually have), but it is in the payload
   * and in every export.
   *
   * - LIST: DataTable + KitPagination, timestamp/actor/action/target/result/detail.
   * - ACTOR SEARCH: MANUAL, never as-you-type. The operator submits with Enter
   *   or the Search button; typing alone changes nothing. This is deliberate —
   *   any `actor` filter puts the endpoint on its slow path (it loads up to
   *   MAX_EVENTS = 10k events into Ruby and matches there), so a debounced
   *   as-you-type box turned every pause into a full-set scan.
   * - ACTION CATEGORY: applies immediately on change. A `<select>` commits one
   *   deliberate value per interaction, so there is nothing to debounce and no
   *   half-typed intermediate state to fire on.
   * - EXPORT: two plain links to `GET /api/colonel/audit/export`, which answers
   *   with a `Content-Disposition: attachment` body (CSV or NDJSON). Links, not
   *   fetch-then-Blob (the AdminUsage pattern), because the rows are on the
   *   server: this screen holds one page, and an export that only covered the
   *   visible page would be a trap. The active filters ride along so the file
   *   matches what the operator is looking at.
   * - READ-ONLY: viewing the log never writes an audit event (CONTRACT 4), so
   *   there are no mutations — and deliberately no way to edit or delete
   *   entries from the UI.
   */
  const { t } = useI18n();

  const store = useColonelAuditLog();
  /**
   * `error` and `validationError` are the two failure modes usePaginatedFetch
   * deliberately keeps apart, and they must NOT collapse into one state here:
   *
   *   - error           the request threw (network/HTTP) → red banner + retry.
   *   - validationError the response ARRIVED but failed Zod → the store degrades
   *                     to `[]`, which would otherwise render as the ordinary
   *                     "No audit events recorded yet" empty state. On an audit
   *                     log that is the worst possible lie: a broken read
   *                     contract reads as "nobody did anything". So the
   *                     mismatch replaces the table outright (below) instead of
   *                     letting the empty state speak for it.
   *
   * They are mutually exclusive by construction — fetchPage nulls both on entry.
   */
  const { events, pagination, loading, error, validationError } = storeToRefs(store);

  // ---- Filters ---------------------------------------------------------------

  /** The raw input value. Editing this NEVER issues a request. */
  const actorTerm = ref('');
  /** The actor term actually applied to the last fetch — the request reads this. */
  const activeActor = ref('');
  const verbCategory = ref('');

  const hasActiveFilters = computed(
    () => actorTerm.value !== '' || activeActor.value !== '' || verbCategory.value !== ''
  );

  /**
   * True when the box holds a term that has not been submitted yet. Manual
   * search means the table can legitimately disagree with the input, so we say
   * so rather than letting the operator read stale rows as a result set.
   */
  const searchPending = computed(() => actorTerm.value.trim() !== activeActor.value);

  /**
   * Action categories = the leading segment of the dotted verbs the ops layer
   * writes (customer.set_role, session.delete, queue.dlq.replay, …).
   *
   * The server matches `verb` as an exact action OR a dotted prefix
   * (list_colonel_audit_events.rb: `verb == filter || verb.start_with?("#{filter}.")`)
   * and validates nothing against an allowlist, so ONE entry here reaches every
   * verb beneath it — `membership` covers membership.add / .remove / .set_role
   * AND the interpolated membership.entitlement.<action> family — and an
   * uncategorised future verb still shows under "All". This list only feeds the
   * convenience select; it is a superset-tolerant menu, not a contract.
   */
  const VERB_CATEGORIES = [
    'customer',
    'session',
    'secret',
    'domain',
    'organization',
    'membership',
    'entitlement_preview',
    'banner',
    'queue',
    'email',
    'ratelimit',
    'ip',
    'colonel',
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

  /**
   * Commit the typed actor term and fetch page 1. The ONLY path from the actor
   * box to a request — bound to Enter (keydown) and to the Search button
   * (submit), so keyboard and mouse have parity. No timers, nothing to clean up
   * on unmount.
   *
   * The term is normalised in place so a stray trailing space cannot leave the
   * "not applied yet" hint stuck on after a successful search.
   */
  function runSearch(): void {
    const term = actorTerm.value.trim();
    actorTerm.value = term;
    activeActor.value = term;
    fetchPage(1);
  }

  /** The action category is a discrete choice — apply it immediately. */
  function onFilterChange(key: string, value: string): void {
    if (key !== 'verb') return;
    verbCategory.value = value;
    fetchPage(1);
  }

  /** Reset every filter (typed and applied) and return to the unfiltered list. */
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

  // ---- Export ----------------------------------------------------------------

  /**
   * Download hrefs for the whole retained trail under the ACTIVE filters (the
   * applied actor term, not the half-typed one). Recomputed as the filters
   * change so the link an operator clicks always matches the table they are
   * reading.
   */
  const exportCsvHref = computed(() =>
    store.exportUrl('csv', {
      actor: activeActor.value || undefined,
      verb: verbCategory.value || undefined,
    })
  );
  const exportNdjsonHref = computed(() =>
    store.exportUrl('ndjson', {
      actor: activeActor.value || undefined,
      verb: verbCategory.value || undefined,
    })
  );

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
    <header
      class="mb-6 flex flex-wrap items-start justify-between gap-4 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <div class="min-w-0">
        <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
          {{ t('web.admin.audit.title') }}
        </h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          {{ t('web.admin.audit.description') }}
        </p>
      </div>

      <!--
        Plain links: the endpoint replies with Content-Disposition: attachment,
        so the browser saves the file and never navigates away. The href carries
        the active filters, and the download is the whole retained trail under
        them — not the visible page.
      -->
      <div class="flex shrink-0 items-center gap-2">
        <a
          :href="exportCsvHref"
          data-testid="audit-export-csv"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-200 dark:hover:bg-gray-800">
          <OIcon
            collection="heroicons"
            name="arrow-down-tray"
            size="4" />
          {{ t('web.admin.audit.export.csv') }}
        </a>
        <a
          :href="exportNdjsonHref"
          data-testid="audit-export-ndjson"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-700 hover:bg-gray-100 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:text-gray-200 dark:hover:bg-gray-800">
          <OIcon
            collection="heroicons"
            name="arrow-down-tray"
            size="4" />
          {{ t('web.admin.audit.export.ndjson') }}
        </a>
      </div>
    </header>

    <p class="mb-4 text-xs text-gray-500 dark:text-gray-400">
      {{ t('web.admin.audit.export.hint') }}
    </p>

    <!-- Network/HTTP error banner. Contract mismatches render below instead. -->
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

    <!--
      Filters: MANUAL actor search (Enter or the Search button) + an action
      category select that applies immediately. `show-search` is off because the
      kit search box is an as-you-type control; the bespoke form below is the
      submit-driven replacement and `order-first` keeps it in the usual
      search-leftmost position.
    -->
    <div class="mb-4">
      <FilterBar
        :show-search="false"
        :filters="filters"
        :has-active-filters="hasActiveFilters"
        testid="audit-filterbar"
        @filter-change="onFilterChange"
        @clear="onClear">
        <form
          class="order-first flex min-w-[18rem] flex-1 flex-wrap items-end gap-2"
          data-testid="audit-actor-form"
          @submit.prevent="runSearch">
          <div class="min-w-0 flex-1">
            <label
              for="audit-actor-input"
              class="font-brand text-[11px] font-semibold tracking-[0.1em] text-gray-500 uppercase dark:text-gray-400">
              {{ t('web.admin.audit.filters.actorLabel') }}
            </label>
            <input
              id="audit-actor-input"
              v-model="actorTerm"
              type="text"
              autocomplete="off"
              spellcheck="false"
              data-testid="audit-actor-input"
              :placeholder="t('web.admin.audit.filters.actorPlaceholder')"
              aria-describedby="audit-actor-hint"
              class="mt-1 block w-full rounded-md border border-gray-300 px-3 py-2 text-sm placeholder:text-gray-400 focus:border-brand-500 focus:ring-1 focus:ring-brand-500 focus:outline-none dark:border-gray-600 dark:bg-gray-800 dark:text-white dark:placeholder:text-gray-500"
              @keydown.enter.prevent="runSearch" />
          </div>
          <button
            type="submit"
            data-testid="audit-actor-search"
            :disabled="loading"
            class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600">
            <OIcon
              collection="heroicons"
              name="magnifying-glass"
              size="4" />
            {{ t('web.admin.audit.filters.searchButton') }}
          </button>
        </form>
      </FilterBar>

      <!-- Announced to screen readers; the visible cue is the pending line. -->
      <p
        id="audit-actor-hint"
        class="sr-only">
        {{ t('web.admin.audit.filters.searchHint') }}
      </p>
      <p
        v-if="searchPending"
        class="mt-2 text-xs text-amber-700 dark:text-amber-300"
        data-testid="audit-search-pending">
        {{ t('web.admin.audit.filters.pendingSearch') }}
      </p>
    </div>

    <!--
      Contract mismatch: the server answered but the payload failed Zod, so the
      store holds `[]` for a reason that has nothing to do with activity. Shown
      INSTEAD of the table so the empty state can never stand in for it.
    -->
    <div
      v-if="validationError"
      class="flex items-center justify-between gap-4 rounded-lg border border-amber-300 bg-amber-50 px-4 py-3 dark:border-amber-800/60 dark:bg-amber-900/20"
      role="alert"
      data-testid="audit-contract-error">
      <span class="text-sm text-amber-800 dark:text-amber-200">
        {{ t('web.admin.audit.list.contractError') }}
      </span>
      <button
        type="button"
        class="inline-flex shrink-0 items-center gap-1 rounded-md border border-amber-400 px-3 py-1.5 text-sm font-medium text-amber-900 hover:bg-amber-100 focus:ring-2 focus:ring-amber-500 focus:outline-none dark:border-amber-700 dark:text-amber-100 dark:hover:bg-amber-900/40"
        @click="fetchPage(1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.audit.list.retry') }}
      </button>
    </div>

    <!-- Table -->
    <div
      v-else
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
