// src/apps/admin/stores/useAdminDlq.ts

import { defineStore } from 'pinia';
import type { z } from 'zod';
import { ref } from 'vue';

import {
  usePaginatedFetch,
  type PageMeta,
  type PageResult,
} from '@/apps/admin/composables/usePaginatedFetch';
import { colonelDlqListResponseSchema } from '@/schemas/api/internal/responses/colonel-queue';
import type { ColonelDlqSummary } from '@/schemas/api/internal/responses/colonel-queue';

type ColonelDlqListResponse = z.infer<typeof colonelDlqListResponseSchema>;

/** One page of dead-letter queues plus the response's broker-connection sidecar. */
interface DlqPageResult extends PageResult<ColonelDlqSummary> {
  connected: boolean | null;
}

/**
 * Per-resource admin store for the dead-letter queue list (#4343).
 *
 * One server page per request over `GET /api/colonel/queues/dlq` (ListDlqs —
 * the configured DLQ allowlist with each queue's depth). `connected` is the
 * broker flag from the same response: when the broker is down the server still
 * lists the queues, with depths it could not read, so the view must say so
 * rather than show a row of zeros as "empty".
 *
 * The per-queue peek and the per-message inspect / replay / discard verbs are
 * view-local (AdminJobs.vue): they act on one drawer's queue, not on this list.
 * ZERO import edge into `src/apps/colonel/*` or `colonelInfoStore`.
 */
export const useAdminDlq = defineStore('adminDlq', () => {
  /** Rows for the current page only (one server page — never accumulated). */
  const dlqs = ref<ColonelDlqSummary[]>([]);
  const pagination = ref<PageMeta | null>(null);
  /** Broker connection flag; null until loaded or when the server omits it. */
  const connected = ref<boolean | null>(null);

  /**
   * Monotonic id of the newest fetchPage call. Responses settle out of order
   * when an operator pages or refreshes while a request is in flight; only
   * the request that still matches this counter may commit state (rows,
   * pagination, `connected`) or clear it on failure, so a slower obsolete
   * response can never replace a newer page or blank it.
   */
  let requestSeq = 0;

  const pager = usePaginatedFetch<ColonelDlqListResponse, ColonelDlqSummary, DlqPageResult>({
    url: '/api/colonel/queues/dlq',
    schema: colonelDlqListResponseSchema,
    context: 'ColonelDlqListResponse',
    select: (data) => ({
      items: data.details?.dlqs ?? [],
      pagination: data.details?.pagination ?? null,
      connected: data.details?.connected ?? null,
    }),
  });

  function clear(): void {
    dlqs.value = [];
    pagination.value = null;
    connected.value = null;
  }

  /**
   * Fetch one page of dead-letter queues.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value
  ): Promise<{ items: ColonelDlqSummary[]; pagination: PageMeta | null } | null> {
    const requestId = ++requestSeq;
    try {
      const result = await pager.fetchPage(targetPage);
      // Stale response: a newer fetchPage owns the state now — hand the result
      // back to this caller but commit nothing.
      if (requestId !== requestSeq) return result;
      if (result) {
        dlqs.value = result.items;
        pagination.value = result.pagination;
        connected.value = result.connected;
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
    dlqs,
    pagination,
    connected,
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
