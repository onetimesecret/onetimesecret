// src/apps/admin/stores/useAdminJobs.ts

import { defineStore } from 'pinia';
import type { z } from 'zod';
import { ref } from 'vue';

import { usePaginatedFetch, type PageMeta } from '@/apps/admin/composables/usePaginatedFetch';
import { colonelJobsResponseSchema } from '@/schemas/api/internal/responses/colonel-jobs';
import type { ColonelJob, ColonelScheduler } from '@/schemas/api/internal/responses/colonel-jobs';

type ColonelJobsResponse = z.infer<typeof colonelJobsResponseSchema>;

/**
 * Per-resource admin store for the scheduler read-out (#4343).
 *
 * Sibling of {@link useColonelAuditLog}: one server page per request over
 * `GET /api/colonel/jobs` (ListJobs — the registered rufus jobs merged with
 * their JobRun records: last ran / next due / last error). The `scheduler`
 * process record rides in the same response's `record` and is kept in
 * lockstep with the page from `select`, the way useAdminSessions keeps `scan`.
 *
 * Read-only: nothing here mutates, and the endpoint records no audit event.
 * ZERO import edge into `src/apps/colonel/*` or `colonelInfoStore`.
 */
export const useAdminJobs = defineStore('adminJobs', () => {
  /** Rows for the current page only (one server page — never accumulated). */
  const jobs = ref<ColonelJob[]>([]);
  const pagination = ref<PageMeta | null>(null);
  /** The scheduler process (liveness, host/pid, job count). Null until loaded. */
  const scheduler = ref<ColonelScheduler | null>(null);

  const pager = usePaginatedFetch<ColonelJobsResponse, ColonelJob>({
    url: '/api/colonel/jobs',
    schema: colonelJobsResponseSchema,
    context: 'ColonelJobsResponse',
    select: (data) => {
      scheduler.value = data.record?.scheduler ?? null;
      return {
        items: data.details?.jobs ?? [],
        pagination: data.details?.pagination ?? null,
      };
    },
  });

  function clear(): void {
    jobs.value = [];
    pagination.value = null;
    scheduler.value = null;
  }

  /**
   * Fetch one page of scheduled jobs.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value
  ): Promise<{ items: ColonelJob[]; pagination: PageMeta | null } | null> {
    try {
      const result = await pager.fetchPage(targetPage);
      if (result) {
        jobs.value = result.items;
        pagination.value = result.pagination;
      } else {
        // Schema mismatch: degrade to empty; pager.validationError names the schema.
        clear();
      }
      return result;
    } catch (err) {
      // Network/HTTP failure: clear stale rows and rethrow for the view to handle.
      clear();
      throw err;
    }
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    clear();
    pager.reset();
  }

  return {
    // State
    jobs,
    pagination,
    scheduler,
    // Fetch state (owned by the shared composable)
    loading: pager.loading,
    error: pager.error,
    validationError: pager.validationError,
    page: pager.page,
    perPage: pager.perPage,
    // Actions
    fetchPage,
    $reset,
  };
});
