// src/apps/admin/stores/useAdminJobs.ts

import { defineStore } from 'pinia';
import type { z } from 'zod';
import { ref } from 'vue';

import {
  usePaginatedFetch,
  type PageMeta,
  type PageResult,
} from '@/apps/admin/composables/usePaginatedFetch';
import { colonelJobsResponseSchema } from '@/schemas/api/internal/responses/colonel-jobs';
import type { ColonelJob, ColonelScheduler } from '@/schemas/api/internal/responses/colonel-jobs';

type ColonelJobsResponse = z.infer<typeof colonelJobsResponseSchema>;

/** One page of jobs plus the response's scheduler-process sidecar. */
interface JobsPageResult extends PageResult<ColonelJob> {
  scheduler: ColonelScheduler | null;
}

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

  /**
   * Monotonic id of the newest fetchPage call. Responses settle out of order
   * when an operator pages or refreshes while a request is in flight; only
   * the request that still matches this counter may commit state (rows,
   * pagination, `scheduler`) or clear it on failure, so a slower obsolete
   * response can never replace a newer page or blank it.
   */
  let requestSeq = 0;

  const pager = usePaginatedFetch<ColonelJobsResponse, ColonelJob, JobsPageResult>({
    url: '/api/colonel/jobs',
    schema: colonelJobsResponseSchema,
    context: 'ColonelJobsResponse',
    select: (data) => ({
      items: data.details?.jobs ?? [],
      pagination: data.details?.pagination ?? null,
      scheduler: data.record?.scheduler ?? null,
    }),
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
    const requestId = ++requestSeq;
    try {
      const result = await pager.fetchPage(targetPage);
      // Stale response: a newer fetchPage owns the state now — hand the result
      // back to this caller but commit nothing.
      if (requestId !== requestSeq) return result;
      if (result) {
        jobs.value = result.items;
        pagination.value = result.pagination;
        scheduler.value = result.scheduler;
      } else {
        // Schema mismatch: degrade to empty; pager.validationError names the schema.
        clear();
      }
      return result;
    } catch (err) {
      // Network/HTTP failure: clear stale rows and rethrow for the view to
      // handle. A superseded request's failure must not blank the newer page.
      if (requestId === requestSeq) clear();
      throw err;
    }
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    // Invalidate any in-flight request so its late settle cannot commit over
    // the freshly reset state.
    requestSeq++;
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
