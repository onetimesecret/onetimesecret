<!-- src/apps/admin/views/AdminJobs.vue -->

<script setup lang="ts">
  import JobsChoresSection from '@/apps/admin/components/jobs/JobsChoresSection.vue';
  import JobsDlqSection from '@/apps/admin/components/jobs/JobsDlqSection.vue';
  import JobsSchedulerSection from '@/apps/admin/components/jobs/JobsSchedulerSection.vue';
  import { useI18n } from 'vue-i18n';

  /**
   * Jobs screen (#4343) — background-work operability in one place:
   *
   *   1. Scheduler — which rufus jobs the running scheduler registered, when
   *      each last ran, when it is next due, and its last error
   *      (`GET /api/colonel/jobs`). Read-only.
   *   2. Dead-letter queues — list → peek drawer → per-message inspect,
   *      replay (tier 2) and discard (tier 1), each by message id.
   *   3. Chores — the allowlisted maintenance chores, with a dry-run preview
   *      where supported and a bounded, confirmed run (tier 2).
   *
   * Each section owns its own fetch, loading / error+retry / loaded states and
   * refresh, so one failing endpoint never blanks the others (the AdminSystem
   * rule). All drawer, dialog and result state is in-page: no query params, so
   * nothing here is subject to the routed view remounting on a query change.
   * AdminSystem stays the read-only status screen; mutations live here.
   */
  const { t } = useI18n();
</script>

<template>
  <div class="mx-auto max-w-6xl">
    <!-- Page header -->
    <header class="mb-6 border-b-2 border-gray-900 pb-4 dark:border-gray-100">
      <h2 class="font-brand text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        {{ t('web.admin.jobs.title') }}
      </h2>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.admin.jobs.description') }}
      </p>
    </header>

    <JobsSchedulerSection />
    <JobsDlqSection />
    <JobsChoresSection />
  </div>
</template>
