<!-- src/apps/admin/components/jobs/JobsSchedulerSection.vue -->

<script setup lang="ts">
  import {
    jobStateBadgeClass,
    formatDurationMs,
    nowSeconds,
    relativeAge,
    runStatusBadgeClass,
    utcTimestamp,
  } from '@/apps/admin/components/jobs/jobsFormat';
  import { DataTable, KitPagination, StatCard } from '@/apps/admin/components/kit';
  import type { DataTableColumn } from '@/apps/admin/components/kit';
  import { useAdminJobs } from '@/apps/admin/stores/useAdminJobs';
  import type { ColonelJob } from '@/schemas/api/internal/responses/colonel-jobs';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Scheduler read-out (#4343, Jobs screen section 1).
   *
   * The scheduler process record (alive / host:pid / job count / heartbeat)
   * plus one row per registered rufus job: last ran, next due, last error. Data
   * comes from {@link useAdminJobs} over `GET /api/colonel/jobs`. Read-only.
   *
   * Relative ages ("5 minutes ago", "in 2 hours") are measured from
   * `referenceNow`, captured when the page of jobs arrives — see jobsFormat.
   */
  const { t } = useI18n();

  const store = useAdminJobs();
  const { jobs, scheduler, pagination, loading, error, validationError } = storeToRefs(store);

  /** Unix seconds the current page was fetched at; the anchor for every age. */
  const referenceNow = ref(nowSeconds());

  const failed = computed(() => error.value !== null || validationError.value !== null);
  const loaded = computed(
    () => !failed.value && (scheduler.value !== null || jobs.value.length > 0)
  );

  async function fetchPage(targetPage = 1): Promise<void> {
    try {
      await store.fetchPage(targetPage);
    } catch {
      // Network/HTTP failure is captured in `store.error`; the banner + retry
      // button below handle it. Swallow so it doesn't become unhandled.
    } finally {
      referenceNow.value = nowSeconds();
    }
  }

  function onPerPageChange(perPage: number): void {
    store.perPage = perPage;
    fetchPage(1);
  }

  const columns = computed<DataTableColumn<ColonelJob>[]>(() => [
    { key: 'job_id', label: t('web.admin.jobs.scheduler.columns.job') },
    { key: 'state', label: t('web.admin.jobs.scheduler.columns.state') },
    { key: 'last_status', label: t('web.admin.jobs.scheduler.columns.lastStatus') },
    { key: 'last_started_at', label: t('web.admin.jobs.scheduler.columns.lastRun') },
    {
      key: 'last_duration_ms',
      label: t('web.admin.jobs.scheduler.columns.duration'),
      align: 'right',
    },
    { key: 'next_time', label: t('web.admin.jobs.scheduler.columns.nextRun') },
    { key: 'run_count', label: t('web.admin.jobs.scheduler.columns.runs'), align: 'right' },
    { key: 'last_error', label: t('web.admin.jobs.scheduler.columns.error') },
  ]);

  const age = (timestamp: number | null): string => relativeAge(timestamp, referenceNow.value);

  /** `every 1h` / `cron 0 3 * * *` — the schedule as registered, or nothing. */
  function scheduleLabel(job: ColonelJob): string {
    if (!job.schedule_expression) return '';
    return [job.schedule_kind, job.schedule_expression].filter(Boolean).join(' ');
  }

  const processLabel = computed(() => {
    const s = scheduler.value;
    if (!s?.host && !s?.pid) return '—';
    return [s.host, s.pid].filter((part) => part !== null && part !== undefined).join(' · ');
  });

  const jobCountLabel = computed(() => {
    const count = scheduler.value?.job_count;
    return typeof count === 'number' ? count.toLocaleString() : '—';
  });

  onMounted(() => fetchPage(1));
</script>

<template>
  <section
    class="mb-10"
    data-testid="jobs-scheduler">
    <div class="mb-3 flex items-end justify-between gap-4">
      <div>
        <h3 class="text-lg font-medium text-gray-900 dark:text-white">
          {{ t('web.admin.jobs.scheduler.title') }}
        </h3>
        <p class="text-xs text-gray-500 dark:text-gray-400">
          {{ t('web.admin.jobs.scheduler.description') }}
        </p>
      </div>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1.5 text-xs font-medium text-gray-700 hover:bg-gray-50 focus:ring-2 focus:ring-brand-500 focus:outline-none disabled:cursor-not-allowed disabled:opacity-50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
        :disabled="loading"
        data-testid="jobs-scheduler-refresh"
        @click="fetchPage(pagination?.page ?? 1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.jobs.refresh') }}
      </button>
    </div>

    <!-- Loading -->
    <div
      v-if="loading && !loaded"
      class="flex items-center gap-3 rounded-lg border border-gray-200 bg-white px-4 py-8 text-sm text-gray-500 dark:border-gray-800 dark:bg-gray-900 dark:text-gray-400"
      data-testid="jobs-scheduler-loading">
      <OIcon
        collection="heroicons"
        name="arrow-path"
        size="5"
        class="animate-spin motion-reduce:animate-none" />
      {{ t('web.COMMON.loading') }}
    </div>

    <!-- Error (network/HTTP or contract mismatch) -->
    <div
      v-else-if="failed"
      class="flex items-center justify-between gap-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 dark:border-red-900/50 dark:bg-red-900/20"
      role="alert"
      data-testid="jobs-scheduler-error">
      <span class="text-sm text-red-800 dark:text-red-200">
        {{ t('web.admin.jobs.scheduler.loadError') }}
      </span>
      <button
        type="button"
        class="inline-flex items-center gap-1 rounded-md border border-red-300 px-3 py-1.5 text-sm font-medium text-red-800 hover:bg-red-100 focus:ring-2 focus:ring-red-500 focus:outline-none dark:border-red-800 dark:text-red-200 dark:hover:bg-red-900/40"
        @click="fetchPage(1)">
        <OIcon
          collection="heroicons"
          name="arrow-path"
          size="4" />
        {{ t('web.admin.jobs.retry') }}
      </button>
    </div>

    <!-- Loaded -->
    <div
      v-else
      class="space-y-4"
      data-testid="jobs-scheduler-loaded">
      <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard
          :label="t('web.admin.jobs.scheduler.stats.status')"
          :value="
            scheduler?.alive
              ? t('web.admin.jobs.scheduler.alive')
              : t('web.admin.jobs.scheduler.notSeen')
          "
          icon="heart"
          testid="jobs-scheduler-status" />
        <StatCard
          :label="t('web.admin.jobs.scheduler.stats.process')"
          :value="processLabel"
          icon="server-stack"
          testid="jobs-scheduler-process" />
        <StatCard
          :label="t('web.admin.jobs.scheduler.stats.jobCount')"
          :value="jobCountLabel"
          icon="rectangle-stack"
          testid="jobs-scheduler-job-count" />
        <StatCard
          :label="t('web.admin.jobs.scheduler.stats.heartbeat')"
          :value="age(scheduler?.heartbeat_at ?? null)"
          icon="clock"
          testid="jobs-scheduler-heartbeat" />
      </div>

      <!-- Not alive: every time below may be stale, so say so before the table. -->
      <p
        v-if="!scheduler?.alive"
        class="flex items-center gap-1 text-xs text-amber-700 dark:text-amber-400"
        data-testid="jobs-scheduler-not-seen">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          size="4" />
        {{ t('web.admin.jobs.scheduler.notSeenHint') }}
      </p>

      <div
        class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-800 dark:bg-gray-900">
        <DataTable
          :columns="columns"
          :rows="jobs"
          row-key="job_id"
          :loading="loading"
          :empty-text="t('web.admin.jobs.scheduler.empty')"
          testid="jobs-table">
          <template #cell-job_id="{ row }">
            <span
              class="block font-mono text-sm text-gray-900 dark:text-white"
              :title="row.job_class">
              {{ row.job_id }}
            </span>
            <span class="block text-xs text-gray-500 dark:text-gray-400">
              {{ t(`web.admin.jobs.scheduler.group.${row.group}`) }}
              <template v-if="scheduleLabel(row)">
                · <span class="font-mono">{{ scheduleLabel(row) }}</span>
              </template>
            </span>
          </template>

          <template #cell-state="{ row }">
            <span
              class="inline-flex rounded px-2 py-0.5 text-xs font-medium"
              :class="jobStateBadgeClass(row.state)"
              :data-testid="`job-state-${row.job_id}`">
              {{ t(`web.admin.jobs.scheduler.state.${row.state}`) }}
            </span>
          </template>

          <template #cell-last_status="{ row }">
            <span
              class="inline-flex rounded px-2 py-0.5 text-xs font-medium"
              :class="runStatusBadgeClass(row.last_status)"
              :data-testid="`job-status-${row.job_id}`">
              {{ t(`web.admin.jobs.status.${row.last_status}`) }}
            </span>
          </template>

          <template #cell-last_started_at="{ row }">
            <span
              class="text-sm text-gray-700 dark:text-gray-300"
              :title="utcTimestamp(row.last_started_at)">
              {{ age(row.last_started_at) }}
            </span>
          </template>

          <template #cell-last_duration_ms="{ row }">
            <span class="font-mono text-xs text-gray-700 tabular-nums dark:text-gray-300">
              {{ formatDurationMs(row.last_duration_ms) }}
            </span>
          </template>

          <template #cell-next_time="{ row }">
            <span
              class="text-sm text-gray-700 dark:text-gray-300"
              :title="utcTimestamp(row.next_time)"
              :data-testid="`job-next-${row.job_id}`">
              {{ age(row.next_time) }}
            </span>
          </template>

          <template #cell-run_count="{ row }">
            <span class="block font-mono text-sm text-gray-900 tabular-nums dark:text-white">
              {{ row.run_count.toLocaleString() }}
            </span>
            <span
              v-if="row.error_count > 0"
              class="block text-xs text-amber-700 dark:text-amber-400">
              {{ t('web.admin.jobs.scheduler.errorCount', { count: row.error_count }) }}
            </span>
          </template>

          <template #cell-last_error="{ row }">
            <span
              v-if="row.last_error"
              class="block max-w-xs truncate font-mono text-xs text-amber-800 dark:text-amber-300"
              :title="row.last_error"
              :data-testid="`job-error-${row.job_id}`">
              {{ row.last_error }}
            </span>
            <span
              v-else
              class="text-xs text-gray-400 dark:text-gray-500">
              —
            </span>
          </template>
        </DataTable>
      </div>

      <KitPagination
        v-if="pagination"
        :pagination="pagination"
        :loading="loading"
        @update:page="fetchPage"
        @update:per-page="onPerPageChange" />
    </div>
  </section>
</template>
