<!-- src/apps/admin/views/AdminUsage.vue -->

<script setup lang="ts">
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { StatCard } from '@/apps/admin/components/kit';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import { usageExportResponseSchema } from '@/schemas/api/internal/responses/colonel-usage';
  import OIcon from '@/shared/components/icons/OIcon.vue';

  /**
   * Usage screen (ticket #33) — a read-only metrics read-out over a date range,
   * the Phase-2 parity port of the legacy `ColonelUsageExport` view rebuilt on
   * the Slice-3 template (no `src/apps/colonel/*` / `colonelInfoStore` imports).
   *
   * Single-GET read-out via {@link useResourceFetch} (CONTRACT 1 — single screens
   * use useResourceFetch), REUSING the frozen `usageExportResponseSchema`
   * (CONTRACT 3). The date range is passed as `start_date` / `end_date` Unix-second
   * params; `load(params)` re-issues the request and `refresh()` repeats the last.
   * Read-only: nothing here mutates, so nothing is audited (CONTRACT 4). The
   * Export buttons serialize the already-loaded payload into real JSON/CSV file
   * downloads client-side — no additional requests.
   *
   * Stub note (spec #33): backend usage counters that are stubbed at 0 upstream
   * are surfaced as-is — this screen never fabricates numbers.
   */
  const { t } = useI18n();

  const startDate = ref('');
  const endDate = ref('');

  const {
    data: usageData,
    loading,
    error,
    validationError,
    load,
  } = useResourceFetch({
    url: '/api/colonel/usage/export',
    schema: usageExportResponseSchema,
    context: 'UsageExportResponse',
  });

  const usage = computed(() => usageData.value?.details ?? null);
  const loadFailed = computed(() => error.value !== null || validationError.value !== null);

  /** ISO yyyy-mm-dd for a Date, for the native date inputs. */
  function toInputDate(date: Date): string {
    return date.toISOString().split('T')[0];
  }

  function applyDefaultDates(): void {
    const end = new Date();
    const start = new Date();
    start.setDate(start.getDate() - 30);
    startDate.value = toInputDate(start);
    endDate.value = toInputDate(end);
  }

  /** Fetch the export for the current date inputs (empty inputs → server default). */
  function fetchUsage(): void {
    const start = startDate.value
      ? Math.floor(new Date(startDate.value).getTime() / 1000)
      : undefined;
    const end = endDate.value
      ? Math.floor(new Date(endDate.value).getTime() / 1000)
      : undefined;
    load({ start_date: start, end_date: end }).catch(() => {});
  }

  // ---- Derived read-out rows ------------------------------------------------

  type DayRow = { date: string; count: number };

  function toSortedRows(map: Record<string, number> | undefined): DayRow[] {
    if (!map) return [];
    return Object.entries(map)
      .map(([date, count]) => ({ date, count }))
      .sort((a, b) => a.date.localeCompare(b.date));
  }

  const secretsByDay = computed<DayRow[]>(() => toSortedRows(usage.value?.secrets_by_day));
  const usersByDay = computed<DayRow[]>(() => toSortedRows(usage.value?.users_by_day));

  const secretsByState = computed(() =>
    Object.entries(usage.value?.usage_data.secrets_by_state ?? {})
      .map(([state, count]) => ({ state, count }))
      .sort((a, b) => b.count - a.count)
  );

  // ---- File export ----------------------------------------------------------
  //
  // "Export" must produce an actual file (QA 2026-07-07: the screen fetched and
  // rendered JSON on-page but never downloaded anything). Client-side only:
  // the loaded payload is serialized into a Blob and saved via a transient
  // anchor — no extra request, nothing mutates (still CONTRACT 4 clean).

  /** Trigger a browser download of `content` as `filename`. */
  function downloadFile(filename: string, mime: string, content: string): void {
    const url = URL.createObjectURL(new Blob([content], { type: mime }));
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    URL.revokeObjectURL(url);
  }

  const exportBasename = computed(
    () => `usage-export_${startDate.value || 'start'}_${endDate.value || 'end'}`
  );

  /** Download the loaded export payload as pretty-printed JSON. */
  function exportJson(): void {
    if (!usage.value) return;
    downloadFile(`${exportBasename.value}.json`, 'application/json', JSON.stringify(usage.value, null, 2));
  }

  /**
   * Download the tabular day-by-day breakdown as CSV (date, secrets,
   * new_users). Dates are ISO yyyy-mm-dd and counts are numbers, so no CSV
   * quoting is needed.
   */
  function exportCsv(): void {
    if (!usage.value) return;
    const secrets = new Map(secretsByDay.value.map((row) => [row.date, row.count]));
    const users = new Map(usersByDay.value.map((row) => [row.date, row.count]));
    const dates = [...new Set([...secrets.keys(), ...users.keys()])].sort();
    const lines = [
      'date,secrets,new_users',
      ...dates.map((date) => `${date},${secrets.get(date) ?? 0},${users.get(date) ?? 0}`),
    ];
    downloadFile(`${exportBasename.value}.csv`, 'text/csv', lines.join('\n'));
  }

  onMounted(() => {
    applyDefaultDates();
    fetchUsage();
  });
</script>

<template>
  <div class="mx-auto max-w-5xl">
    <!-- Page header -->
    <div class="mb-6">
      <h2 class="font-brand text-2xl font-semibold text-gray-900 dark:text-white">
        {{ t('web.admin.usage.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.usage.description') }}
      </p>
    </div>

    <!-- Date-range selector -->
    <div
      class="mb-6 rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="usage-range">
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div>
          <label
            for="usage-start"
            class="mb-1 block text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.usage.startDate') }}
          </label>
          <input
            id="usage-start"
            v-model="startDate"
            type="date"
            data-testid="usage-start"
            class="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <div>
          <label
            for="usage-end"
            class="mb-1 block text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {{ t('web.admin.usage.endDate') }}
          </label>
          <input
            id="usage-end"
            v-model="endDate"
            type="date"
            data-testid="usage-end"
            class="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-brand-500 focus:outline-none focus:ring-1 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-white" />
        </div>
        <div class="flex items-end">
          <button
            type="button"
            data-testid="usage-fetch"
            :disabled="loading"
            class="inline-flex w-full items-center justify-center gap-1 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
            @click="fetchUsage">
            <OIcon
              v-if="loading"
              collection="heroicons"
              name="arrow-path"
              size="4"
              class="animate-spin motion-reduce:animate-none" />
            {{ loading ? t('web.COMMON.loading') : t('web.admin.usage.fetch') }}
          </button>
        </div>
      </div>
    </div>

    <!-- Error -->
    <div
      v-if="loadFailed"
      class="mb-4 flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="usage-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.usage.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:outline-none focus:ring-2 focus:ring-red-500 dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="fetchUsage">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.usage.retry') }}
      </button>
    </div>

    <!-- Loaded -->
    <div
      v-if="usage"
      class="space-y-6"
      data-testid="usage-content">
      <!-- Export downloads -->
      <div class="flex justify-end gap-2">
        <button
          type="button"
          data-testid="usage-export-json"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200 dark:hover:bg-gray-700"
          @click="exportJson">
          <OIcon
            collection="heroicons"
            name="arrow-down"
            size="4" />
          {{ t('web.admin.usage.exportJson') }}
        </button>
        <button
          type="button"
          data-testid="usage-export-csv"
          class="inline-flex items-center gap-1 rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-800 dark:text-gray-200 dark:hover:bg-gray-700"
          @click="exportCsv">
          <OIcon
            collection="heroicons"
            name="arrow-down"
            size="4" />
          {{ t('web.admin.usage.exportCsv') }}
        </button>
      </div>

      <!-- Summary tiles -->
      <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard
          :label="t('web.admin.usage.stats.totalSecrets')"
          :value="usage.usage_data.total_secrets.toLocaleString()"
          icon="key"
          testid="usage-total-secrets" />
        <StatCard
          :label="t('web.admin.usage.stats.newUsers')"
          :value="usage.usage_data.total_new_users.toLocaleString()"
          icon="user-plus"
          testid="usage-new-users" />
        <StatCard
          :label="t('web.admin.usage.stats.avgSecrets')"
          :value="usage.usage_data.avg_secrets_per_day.toFixed(1)"
          testid="usage-avg-secrets" />
        <StatCard
          :label="t('web.admin.usage.stats.avgUsers')"
          :value="usage.usage_data.avg_users_per_day.toFixed(1)"
          testid="usage-avg-users" />
      </div>

      <!-- Secrets by state -->
      <section
        v-if="secretsByState.length > 0"
        class="rounded-lg border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-800 dark:bg-gray-900"
        data-testid="usage-by-state">
        <h3 class="mb-3 text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
          {{ t('web.admin.usage.byState') }}
        </h3>
        <div class="flex flex-wrap gap-2">
          <span
            v-for="row in secretsByState"
            :key="row.state"
            class="inline-flex items-center gap-1.5 rounded bg-gray-100 px-2.5 py-1 text-sm text-gray-700 dark:bg-gray-800 dark:text-gray-300">
            <span class="font-mono">{{ row.state }}</span>
            <span class="font-semibold text-gray-900 dark:text-white">{{ row.count.toLocaleString() }}</span>
          </span>
        </div>
      </section>

      <!-- Daily breakdowns -->
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <!-- Secrets by day -->
        <section
          class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
          <div class="border-b border-gray-200 px-5 py-3 dark:border-gray-800">
            <h3 class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t('web.admin.usage.secretsByDay') }}
            </h3>
          </div>
          <div class="max-h-96 overflow-y-auto">
            <table class="min-w-full">
              <thead class="sticky top-0 bg-gray-50 dark:bg-gray-800">
                <tr>
                  <th class="px-5 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400">
                    {{ t('web.admin.usage.columns.date') }}
                  </th>
                  <th class="px-5 py-2 text-right text-xs font-medium text-gray-500 dark:text-gray-400">
                    {{ t('web.admin.usage.columns.count') }}
                  </th>
                </tr>
              </thead>
              <tbody
                class="divide-y divide-gray-200 dark:divide-gray-800"
                data-testid="usage-secrets-by-day">
                <tr v-if="secretsByDay.length === 0">
                  <td
                    colspan="2"
                    class="px-5 py-6 text-center text-sm text-gray-500 dark:text-gray-400">
                    {{ t('web.admin.usage.empty') }}
                  </td>
                </tr>
                <tr
                  v-for="row in secretsByDay"
                  :key="row.date">
                  <td class="px-5 py-1.5 text-sm text-gray-900 dark:text-white">{{ row.date }}</td>
                  <td class="px-5 py-1.5 text-right font-mono text-sm text-gray-900 dark:text-white">
                    {{ row.count.toLocaleString() }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <!-- New users by day -->
        <section
          class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
          <div class="border-b border-gray-200 px-5 py-3 dark:border-gray-800">
            <h3 class="text-sm font-medium text-gray-900 dark:text-white">
              {{ t('web.admin.usage.usersByDay') }}
            </h3>
          </div>
          <div class="max-h-96 overflow-y-auto">
            <table class="min-w-full">
              <thead class="sticky top-0 bg-gray-50 dark:bg-gray-800">
                <tr>
                  <th class="px-5 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400">
                    {{ t('web.admin.usage.columns.date') }}
                  </th>
                  <th class="px-5 py-2 text-right text-xs font-medium text-gray-500 dark:text-gray-400">
                    {{ t('web.admin.usage.columns.count') }}
                  </th>
                </tr>
              </thead>
              <tbody
                class="divide-y divide-gray-200 dark:divide-gray-800"
                data-testid="usage-users-by-day">
                <tr v-if="usersByDay.length === 0">
                  <td
                    colspan="2"
                    class="px-5 py-6 text-center text-sm text-gray-500 dark:text-gray-400">
                    {{ t('web.admin.usage.empty') }}
                  </td>
                </tr>
                <tr
                  v-for="row in usersByDay"
                  :key="row.date">
                  <td class="px-5 py-1.5 text-sm text-gray-900 dark:text-white">{{ row.date }}</td>
                  <td class="px-5 py-1.5 text-right font-mono text-sm text-gray-900 dark:text-white">
                    {{ row.count.toLocaleString() }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>
