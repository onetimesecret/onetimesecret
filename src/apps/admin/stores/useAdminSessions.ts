// src/apps/admin/stores/useAdminSessions.ts

import { defineStore } from 'pinia';
import type { z } from 'zod';
import { ref } from 'vue';

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import { colonelSessionsResponseSchema } from '@/schemas/api/internal/responses/colonel-sessions';
import type { ColonelSession } from '@/schemas/api/account/responses/colonel-sessions';

type ColonelSessionsResponse = z.infer<typeof colonelSessionsResponseSchema>;

/**
 * Per-resource admin store for active sessions (ticket #40, CONTRACT 3).
 *
 * Sibling of {@link useAdminCustomers}: one server page
 * per request over the NEW `GET /api/colonel/sessions` endpoint (a thin adapter
 * over `Onetime::Operations::Sessions::List` — bounded scan, #2211). The endpoint
 * supports an optional server-side `search` filter across session identity fields;
 * the view drives it through {@link fetchPage}. ZERO import edge into
 * `src/apps/colonel/*` or `colonelInfoStore.ts`.
 */
export const useAdminSessions = defineStore('adminSessions', () => {
  /** Rows for the current page only (one server page — never accumulated). */
  const sessions = ref<ColonelSession[]>([]);
  const pagination = ref<PageMeta | null>(null);

  const pager = usePaginatedFetch<ColonelSessionsResponse, ColonelSession>({
    url: '/api/colonel/sessions',
    schema: colonelSessionsResponseSchema,
    context: 'ColonelSessionsResponse',
    select: (data) => ({
      items: data.details?.sessions ?? [],
      pagination: data.details?.pagination ?? null,
    }),
  });

  /**
   * Fetch one page of sessions, optionally filtered by a free-text search term.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @param search optional identity filter (email / external id).
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value,
    search?: string
  ): Promise<{ items: ColonelSession[]; pagination: PageMeta | null } | null> {
    try {
      const result = await pager.fetchPage(
        targetPage,
        search ? { search } : undefined
      );
      if (result) {
        sessions.value = result.items;
        pagination.value = result.pagination;
      } else {
        // Schema mismatch: degrade to empty; pager.validationError names the schema.
        sessions.value = [];
        pagination.value = null;
      }
      return result;
    } catch (err) {
      // Network/HTTP failure: clear stale rows and rethrow for the view to handle.
      sessions.value = [];
      pagination.value = null;
      throw err;
    }
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    sessions.value = [];
    pagination.value = null;
    pager.reset();
  }

  return {
    // State
    sessions,
    pagination,
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
