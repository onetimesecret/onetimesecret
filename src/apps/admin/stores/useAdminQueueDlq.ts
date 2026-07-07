// src/apps/admin/stores/useAdminQueueDlq.ts

import { defineStore } from 'pinia';
import type { z } from 'zod';
import { ref } from 'vue';

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import { colonelDlqListResponseSchema } from '@/schemas/api/internal/responses/colonel-queue';
import type { ColonelDlqSummary } from '@/schemas/api/account/responses/colonel-queue';

type ColonelDlqListResponse = z.infer<typeof colonelDlqListResponseSchema>;

/**
 * Per-resource admin store for the dead-letter-queue console (ticket #42,
 * CONTRACT 3).
 *
 * Sibling of {@link useAdminSessions}: one server page per request over the NEW
 * `GET /api/colonel/queues/dlq` endpoint (a thin adapter over
 * `Onetime::Operations::Dlq::List`). The DLQ set is the fixed configured
 * allowlist (bounded by construction — CONTRACT 6), so a single page normally
 * holds every queue; pagination is kept for kit uniformity. ZERO import edge into
 * `src/apps/colonel/*` or `colonelInfoStore.ts`.
 */
export const useAdminQueueDlq = defineStore('adminQueueDlq', () => {
  /** Rows for the current page only (one server page — never accumulated). */
  const dlqs = ref<ColonelDlqSummary[]>([]);
  const pagination = ref<PageMeta | null>(null);
  /** Whether the broker was reachable on the last fetch (informational banner). */
  const connected = ref<boolean | null>(null);

  const pager = usePaginatedFetch<ColonelDlqListResponse, ColonelDlqSummary>({
    url: '/api/colonel/queues/dlq',
    schema: colonelDlqListResponseSchema,
    context: 'ColonelDlqListResponse',
    select: (data) => {
      // Side-effect: capture the broker-reachability flag off the validated
      // response so the disconnected banner can render. `select` is the only
      // hook that receives the full payload (fetchPage sees just items +
      // pagination), so the flag is surfaced here rather than dropped.
      connected.value = data.details?.connected ?? null;
      return {
        items: data.details?.dlqs ?? [],
        pagination: data.details?.pagination ?? null,
      };
    },
  });

  /**
   * Fetch one page of DLQ summaries.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value
  ): Promise<{ items: ColonelDlqSummary[]; pagination: PageMeta | null } | null> {
    try {
      const result = await pager.fetchPage(targetPage);
      if (result) {
        dlqs.value = result.items;
        pagination.value = result.pagination;
      } else {
        // Schema mismatch: degrade to empty; pager.validationError names the schema.
        // `select` never ran, so clear the stale broker flag too.
        dlqs.value = [];
        pagination.value = null;
        connected.value = null;
      }
      return result;
    } catch (err) {
      // Network/HTTP failure: clear stale rows + broker flag and rethrow.
      dlqs.value = [];
      pagination.value = null;
      connected.value = null;
      throw err;
    }
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    dlqs.value = [];
    pagination.value = null;
    connected.value = null;
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
