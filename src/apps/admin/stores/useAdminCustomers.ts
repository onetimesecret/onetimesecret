// src/apps/admin/stores/useAdminCustomers.ts

import { defineStore } from 'pinia';
import type { z } from 'zod';
import { ref } from 'vue';

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import { colonelUsersResponseSchema } from '@/schemas/api/internal/responses/colonel';
import type { ColonelUser } from '@/schemas/api/account/responses/colonel';

type ColonelUsersResponse = z.infer<typeof colonelUsersResponseSchema>;

/**
 * Per-resource admin store for customers/users (CONTRACT 3).
 *
 * Backed by the `GET /api/colonel/users` endpoint and
 * `colonelUsersResponseSchema`. The endpoint supports an optional server-side
 * `search` param (email lookup via a bounded index scan) alongside the `role`
 * filter; the view drives both through {@link fetchPage}. Owns ONLY this
 * resource — loading/page/error come from the shared paginated-fetch
 * composable, so adding the next resource is a copy of this ~40-line file, not
 * an edit to a shared god-store.
 *
 * Isolation: this module has ZERO import edge into `src/apps/colonel/*` or
 * `src/shared/stores/colonelInfoStore.ts` (enforced by an architecture test),
 * so it never drags the retiring legacy tree into the admin bundle.
 */
export const useAdminCustomers = defineStore('adminCustomers', () => {
  /** Rows for the current page only (one server page — never accumulated). */
  const customers = ref<ColonelUser[]>([]);
  const pagination = ref<PageMeta | null>(null);

  const pager = usePaginatedFetch<ColonelUsersResponse, ColonelUser>({
    url: '/api/colonel/users',
    schema: colonelUsersResponseSchema,
    context: 'ColonelUsersResponse',
    select: (data) => ({
      items: data.details?.users ?? [],
      pagination: data.details?.pagination ?? null,
    }),
  });

  /**
   * Fetch one page of customers.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @param roleFilter optional `role` server filter (e.g. 'colonel').
   * @param search optional email search term (server-side, bounded index scan).
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value,
    roleFilter?: string,
    search?: string
  ): Promise<{ items: ColonelUser[]; pagination: PageMeta | null } | null> {
    try {
      const params: Record<string, string> = {};
      if (roleFilter) params.role = roleFilter;
      if (search) params.search = search;
      const result = await pager.fetchPage(
        targetPage,
        Object.keys(params).length > 0 ? params : undefined
      );
      if (result) {
        customers.value = result.items;
        pagination.value = result.pagination;
      } else {
        // Schema mismatch: degrade to empty; pager.validationError names the schema.
        customers.value = [];
        pagination.value = null;
      }
      return result;
    } catch (err) {
      // Network/HTTP failure: clear stale rows and rethrow for the view to handle.
      customers.value = [];
      pagination.value = null;
      throw err;
    }
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    customers.value = [];
    pagination.value = null;
    pager.reset();
  }

  return {
    // State
    customers,
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
