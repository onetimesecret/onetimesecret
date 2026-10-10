<!-- src/apps/admin/components/jobs/JobsChoresSection.vue -->

<script setup lang="ts">
  import {
    formatDurationMs,
    nowSeconds,
    relativeAge,
    runStatusBadgeClass,
    utcTimestamp,
  } from '@/apps/admin/components/jobs/jobsFormat';
  import { AdminConfirmDialog, DataTable, JsonViewer } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminDestructiveMutation } from '@/apps/admin/composables/useAdminDestructiveMutation';
  import { useAdminMutation } from '@/apps/admin/composables/useAdminMutation';
  import { useResourceFetch } from '@/apps/admin/composables/useResourceFetch';
  import { confirmHeaders } from '@/apps/admin/utils/confirmHeader';
  import { reasonBody } from '@/apps/admin/utils/operatorReason';
  import type {
    ColonelChore,
    ColonelChoreRunDetails,
    ColonelChoreRunRecord,
  } from '@/schemas/api/internal/responses/colonel-jobs';
  import {
    colonelChoreRunResponseSchema,
    colonelChoresResponseSchema,
  } from '@/schemas/api/internal/responses/colonel-jobs';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import CopyButton from '@/shared/components/ui/CopyButton.vue';
  import { useApi } from '@/shared/composables/useApi';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { gracefulParse } from '@/utils/schemaValidation';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * On-demand chores (#4343, Jobs screen section 3).
   *
   * The server's chore allowlist (`GET /api/colonel/chores`), one row per
   * chore id, each with the equivalent CLI command. Two verbs:
   *
   * - PREVIEW (only where `supports_dry_run`): `dry_run: true`, no
   *   confirmation, writes nothing. Goes through {@link useAdminMutation} so it
   *   gets the same loading/error handling as every other admin call.
   * - RUN (tier 2): typed confirmation on the chore id + optional reason + a
   *   record limit. The run is synchronous and bounded twice — by the limit and
   *   by a server wall-clock budget — so the result says whether it stopped
   *   early (`capped`, `budget_exhausted`) and the counts are partial. The CLI
   *   command is the full-fleet path.
   *
   * The result panel is in-page state (never the query string).
   */
  const { t } = useI18n();
  const $api = useApi();
  const notifications = useNotificationsStore();

  /** Records a console run touches by default — small, to stay inside the budget. */
  const CHORE_DEFAULT_LIMIT = 100;
  /** Upper bound the server accepts for `limit` (Chores::Run::MAX_LIMIT). */
  const CHORE_MAX_LIMIT = 1000;

  const {
    data: choresData,
    loading,
    error,
    validationError,
    load,
  } = useResourceFetch({
    url: '/api/colonel/chores',
    schema: colonelChoresResponseSchema,
    context: 'ColonelChoresResponse',
  });

  const chores = computed(() => choresData.value?.details?.chores ?? []);
  const failed = computed(() => error.value !== null || validationError.value !== null);

  /** Unix seconds the list was fetched at; the anchor for "last run" ages. */
  const referenceNow = ref(nowSeconds());

  async function loadChores(): Promise<void> {
    try {
      await load();
    } catch {
      // Captured in `error`; the banner + retry handle it.
    } finally {
      referenceNow.value = nowSeconds();
    }
  }

  const columns = computed<DataTableColumn<ColonelChore>[]>(() => [
    { key: 'id', label: t('web.admin.jobs.chores.columns.chore') },
    { key: 'kind', label: t('web.admin.jobs.chores.columns.kind') },
    { key: 'last_started_at', label: t('web.admin.jobs.chores.columns.lastRun') },
    { key: 'last_status', label: t('web.admin.jobs.chores.columns.lastStatus') },
    { key: 'actions', label: t('web.admin.jobs.chores.columns.actions'), align: 'right' },
  ]);

  function runUrl(choreId: string): string {
    return `/api/colonel/chores/${encodeURIComponent(choreId)}/run`;
  }

  // ---- Result panel -----------------------------------------------------------

  interface ChoreResult {
    chore: string;
    /** Null when the 2xx ack did not match its schema — outcome unknown. */
    record: ColonelChoreRunRecord | null;
    details: ColonelChoreRunDetails | null;
  }

  const result = ref<ChoreResult | null>(null);

  function captureResult(choreId: string, payload: unknown): void {
    const parsed = gracefulParse(colonelChoreRunResponseSchema, payload, 'ColonelChoreRunResponse');
    result.value = parsed.ok
      ? { chore: choreId, record: parsed.data.record, details: parsed.data.details ?? null }
      : { chore: choreId, record: null, details: null };
  }

  /** True when the run stopped early for either bound — counts are partial. */
  const resultPartial = computed(
    () => result.value?.record?.capped === true || result.value?.record?.budget_exhausted === true
  );

  /**
   * True when the status itself is not a clean finish: a run that is not
   * `success` (partial / skipped / aborted / anything new), or a preview whose
   * status is not `dry_run`. Drives the status colour in the result panel.
   */
  const resultStatusAttention = computed(() => {
    const record = result.value?.record;
    if (!record) return false;
    return record.status !== (record.dry_run ? 'dry_run' : 'success');
  });

  /**
   * One notification for a finished run, matched to what it reported. Only a
   * `success` run that tripped neither bound is green.
   */
  function notifyRun(record: ColonelChoreRunRecord | null): void {
    if (!record) {
      notifications.show(t('web.admin.jobs.chores.result.unverified'), 'warning');
      return;
    }
    switch (record.status) {
      case 'success':
        if (resultPartial.value) {
          notifications.show(t('web.admin.jobs.chores.run.partial'), 'warning');
        } else {
          notifications.show(t('web.admin.jobs.chores.run.success'), 'success');
        }
        break;
      case 'partial':
        notifications.show(t('web.admin.jobs.chores.run.someFailed'), 'warning');
        break;
      case 'skipped':
        notifications.show(t('web.admin.jobs.chores.run.skipped'), 'warning');
        break;
      case 'aborted':
        notifications.show(t('web.admin.jobs.chores.run.aborted'), 'error');
        break;
      default:
        notifications.show(
          t('web.admin.jobs.chores.run.otherStatus', { status: record.status }),
          'warning'
        );
    }
  }

  // ---- Preview (dry run, no confirmation) -------------------------------------

  /** The chore whose preview is in flight or last failed. */
  const previewChore = ref<string | null>(null);

  const {
    loading: previewLoading,
    error: previewError,
    run: runPreview,
  } = useAdminMutation(async (chore: ColonelChore) => {
    const response = await $api.post(runUrl(chore.id), {
      dry_run: true,
      limit: CHORE_DEFAULT_LIMIT,
    });
    captureResult(chore.id, response.data);
  });

  async function preview(chore: ColonelChore): Promise<void> {
    previewChore.value = chore.id;
    result.value = null;
    await runPreview(chore);
  }

  // ---- Run (guarded, tier 2) --------------------------------------------------

  const runDialogOpen = ref(false);
  const runTarget = ref<ColonelChore | null>(null);
  /** Bound to a number input; v-model.number leaves a string when unparsable. */
  const runLimit = ref<number | string>(CHORE_DEFAULT_LIMIT);
  const runLimitValue = computed(() => Number(runLimit.value));
  const limitInvalid = computed(
    () =>
      !Number.isInteger(runLimitValue.value) ||
      runLimitValue.value < 1 ||
      runLimitValue.value > CHORE_MAX_LIMIT
  );

  const {
    loading: runLoading,
    error: runError,
    run: runChore,
    reset: resetRun,
  } = useAdminDestructiveMutation(async (reason?: string) => {
    const chore = runTarget.value;
    if (!chore) throw new Error('No chore selected');
    // The chore id the operator retyped is the X-OTS-Confirm token (#4326);
    // the server confirms against its sanitized `params['chore']`.
    const response = await $api.post(
      runUrl(chore.id),
      { dry_run: false, limit: runLimitValue.value, ...reasonBody(reason) },
      { headers: confirmHeaders(chore.id) }
    );
    captureResult(chore.id, response.data);
  });

  function requestRun(chore: ColonelChore): void {
    runTarget.value = chore;
    runLimit.value = CHORE_DEFAULT_LIMIT;
    // A stale result must never read as this run's outcome.
    result.value = null;
    previewChore.value = null;
    resetRun();
    runDialogOpen.value = true;
  }

  async function onRunConfirm(reason?: string): Promise<void> {
    if (limitInvalid.value) return; // The inline hint under the input says why.
    const ok = await runChore(reason);
    if (!ok) return; // Failure message stays in the dialog for retry/cancel.

    // The dialog closes on every acknowledged run; the result panel below stays
    // up with the status and report until dismissed or the next run.
    runDialogOpen.value = false;
    notifyRun(result.value?.record ?? null);
    await loadChores();
  }

  function onRunCancel(): void {
    runDialogOpen.value = false;
    resetRun();
  }

  onMounted(loadChores);
</script>

<template>
  <section data-testid="jobs-chores">
    <div class="mb-3 flex items-end justify-between gap-4">
      <div>
        <h3 class="text-lg font-medium text-gray-900 dark:text-white">
          {{ t('web.admin.jobs.chores.title') }}
        </h3>
        <p class="text-xs text-gray-500 dark:text-gray-400">
          {{ t('web.admin.jobs.chores.description') }}
        </p>
      </div>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
        :disabled="loading"
        data-testid="jobs-chores-refresh"
        @click="loadChores">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.jobs.refresh') }}
      </button>
    </div>

    <!-- Error (network/HTTP or contract mismatch) -->
    <div
      v-if="failed"
      class="flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="jobs-chores-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.jobs.chores.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="loadChores">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.jobs.retry') }}
      </button>
    </div>

    <div
      v-else
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
      <DataTable
        :columns="columns"
        :rows="chores"
        row-key="id"
        :loading="loading"
        :empty-text="t('web.admin.jobs.chores.empty')"
        testid="chores-table">
        <template #cell-id="{ row }">
          <span class="block font-mono text-sm text-gray-900 dark:text-white">{{ row.id }}</span>
          <!-- The equivalent full-fleet CLI command, copyable. -->
          <span class="mt-1 flex items-center gap-1">
            <code
              class="font-mono text-xs break-all text-gray-500 dark:text-gray-400"
              :data-testid="`chore-cli-${row.id}`">
              {{ row.cli }}
            </code>
            <CopyButton :text="row.cli" />
          </span>
        </template>

        <template #cell-kind="{ row }">
          <span class="block text-sm text-gray-700 dark:text-gray-300">
            {{ t(`web.admin.jobs.chores.kind.${row.kind}`) }}
          </span>
          <span class="block font-mono text-xs text-gray-500 dark:text-gray-400">
            {{ row.model }}
          </span>
        </template>

        <template #cell-last_started_at="{ row }">
          <span
            class="text-sm text-gray-700 dark:text-gray-300"
            :title="utcTimestamp(row.last_started_at)">
            {{ relativeAge(row.last_started_at, referenceNow) }}
          </span>
        </template>

        <template #cell-last_status="{ row }">
          <span
            class="inline-flex rounded px-2 py-0.5 text-xs font-medium"
            :class="runStatusBadgeClass(row.last_status)"
            :data-testid="`chore-status-${row.id}`">
            {{ t(`web.admin.jobs.status.${row.last_status}`) }}
          </span>
          <span
            v-if="row.last_error"
            class="mt-1 block max-w-xs truncate font-mono text-xs text-amber-800 dark:text-amber-300"
            :title="row.last_error">
            {{ row.last_error }}
          </span>
        </template>

        <template #cell-actions="{ row }">
          <div class="flex justify-end gap-2">
            <button
              v-if="row.supports_dry_run"
              type="button"
              class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
              :disabled="previewLoading"
              :data-testid="`chore-preview-${row.id}`"
              @click="preview(row)">
              <OIcon
                collection="heroicons"
                name="eye"
                size="4" />
              {{ t('web.admin.jobs.chores.preview.button') }}
            </button>
            <button
              type="button"
              class="inline-flex items-center gap-1 rounded-md bg-brand-600 px-2.5 py-1.5 text-xs font-medium text-white hover:bg-brand-700 focus:ring-2 focus:ring-brand-500 focus:ring-offset-1 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-600"
              :data-testid="`chore-run-${row.id}`"
              @click="requestRun(row)">
              <OIcon
                collection="heroicons"
                name="arrow-path"
                size="4" />
              {{ t('web.admin.jobs.chores.run.button') }}
            </button>
          </div>
        </template>
      </DataTable>
    </div>

    <!-- Preview failure (the request itself failed; nothing was written). -->
    <div
      v-if="previewError && previewChore"
      class="mt-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800 dark:border-amber-900/50 dark:bg-amber-900/20 dark:text-amber-200"
      role="alert"
      data-testid="chores-preview-error">
      {{ t('web.admin.jobs.chores.preview.failed', { chore: previewChore }) }}
      <span class="block font-mono text-xs">{{ previewError }}</span>
    </div>

    <!-- Result of the last preview or run -->
    <div
      v-if="result"
      class="mt-4 rounded-lg border border-gray-200 bg-white p-4 shadow-sm dark:border-gray-800 dark:bg-gray-900"
      data-testid="chores-result">
      <div class="flex items-start justify-between gap-3">
        <h4 class="text-xs font-medium tracking-wider text-gray-500 uppercase dark:text-gray-400">
          {{ t('web.admin.jobs.chores.result.title') }}
          <span class="ml-1 font-mono tracking-normal text-gray-900 normal-case dark:text-white">{{
            result.chore
          }}</span>
        </h4>
        <button
          type="button"
          class="text-xs font-medium text-gray-500 hover:text-gray-700 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-400 dark:hover:text-gray-200"
          data-testid="chores-result-dismiss"
          @click="result = null">
          {{ t('web.admin.jobs.chores.result.dismiss') }}
        </button>
      </div>

      <p
        v-if="!result.record"
        class="mt-2 text-sm text-amber-800 dark:text-amber-300"
        data-testid="chores-result-unverified">
        {{ t('web.admin.jobs.chores.result.unverified') }}
      </p>

      <div
        v-else
        class="mt-2 space-y-3 text-sm">
        <dl class="grid grid-cols-2 gap-x-6 gap-y-2 sm:grid-cols-4">
          <div>
            <dt class="text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.admin.jobs.chores.result.status') }}
            </dt>
            <dd
              class="mt-0.5 font-mono"
              :class="
                resultStatusAttention
                  ? 'text-amber-800 dark:text-amber-300'
                  : 'text-gray-900 dark:text-white'
              "
              data-testid="chores-result-status">
              {{ t(`web.admin.jobs.chores.status.${result.record.status}`, result.record.status) }}
            </dd>
          </div>
          <div>
            <dt class="text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.admin.jobs.chores.result.limit') }}
            </dt>
            <dd class="mt-0.5 font-mono text-gray-900 tabular-nums dark:text-white">
              {{ result.record.limit.toLocaleString() }}
            </dd>
          </div>
          <div>
            <dt class="text-xs text-gray-500 dark:text-gray-400">
              {{ t('web.admin.jobs.chores.result.duration') }}
            </dt>
            <dd class="mt-0.5 font-mono text-gray-900 tabular-nums dark:text-white">
              {{ formatDurationMs(result.record.duration_ms) }}
            </dd>
          </div>
        </dl>

        <p
          v-if="result.record.dry_run"
          class="text-gray-700 dark:text-gray-300"
          data-testid="chores-result-preview">
          {{ t('web.admin.jobs.chores.result.preview') }}
        </p>
        <p
          v-if="result.record.capped"
          class="flex items-start gap-1 text-amber-800 dark:text-amber-300"
          data-testid="chores-result-capped">
          <OIcon
            collection="heroicons"
            name="exclamation-triangle"
            size="4"
            class="mt-0.5 shrink-0" />
          {{ t('web.admin.jobs.chores.result.capped', { limit: result.record.limit }) }}
        </p>
        <p
          v-if="result.record.budget_exhausted"
          class="flex items-start gap-1 text-amber-800 dark:text-amber-300"
          data-testid="chores-result-budget">
          <OIcon
            collection="heroicons"
            name="exclamation-triangle"
            size="4"
            class="mt-0.5 shrink-0" />
          {{ t('web.admin.jobs.chores.result.budgetExhausted') }}
        </p>

        <JsonViewer
          v-if="result.details"
          :data="result.details.report"
          :expand-depth="2"
          testid="chores-result-report" />

        <div
          v-if="result.details?.cli"
          class="rounded border border-gray-200 px-3 py-2 text-xs dark:border-gray-700">
          <span class="text-gray-500 dark:text-gray-400">
            {{ t('web.admin.jobs.chores.result.cli') }}
          </span>
          <span class="mt-1 flex items-center gap-1">
            <code
              class="font-mono break-all text-gray-900 dark:text-white"
              data-testid="chores-result-cli">
              {{ result.details.cli }}
            </code>
            <CopyButton :text="result.details.cli" />
          </span>
        </div>
      </div>
    </div>

    <!-- Typed-confirmation run gate (tier 2: not destructive, so not danger). -->
    <AdminConfirmDialog
      v-model:open="runDialogOpen"
      :title="t('web.admin.jobs.chores.run.confirmTitle')"
      :confirm-token="runTarget?.id ?? ''"
      :confirm-text="t('web.admin.jobs.chores.run.button')"
      request-reason
      :loading="runLoading"
      :error="runError"
      @confirm="onRunConfirm"
      @cancel="onRunCancel">
      <template #description>
        <div class="space-y-3 text-sm text-gray-600 dark:text-gray-300">
          <p>
            {{ t('web.admin.jobs.chores.run.confirmDescription', { chore: runTarget?.id ?? '' }) }}
          </p>
          <div>
            <label
              for="chore-run-limit"
              class="block text-xs font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.admin.jobs.chores.run.limitLabel') }}
            </label>
            <input
              id="chore-run-limit"
              v-model.number="runLimit"
              type="number"
              min="1"
              :max="CHORE_MAX_LIMIT"
              step="1"
              inputmode="numeric"
              class="mt-1 block w-32 rounded-md border-gray-300 font-mono text-sm shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white"
              :aria-invalid="limitInvalid ? 'true' : undefined"
              aria-describedby="chore-run-limit-hint"
              :disabled="runLoading"
              data-testid="chore-run-limit" />
            <p
              id="chore-run-limit-hint"
              class="mt-1 text-xs"
              :class="
                limitInvalid
                  ? 'text-amber-700 dark:text-amber-400'
                  : 'text-gray-500 dark:text-gray-400'
              ">
              {{ t('web.admin.jobs.chores.run.limitHint', { max: CHORE_MAX_LIMIT }) }}
            </p>
          </div>
        </div>
      </template>
    </AdminConfirmDialog>
  </section>
</template>
