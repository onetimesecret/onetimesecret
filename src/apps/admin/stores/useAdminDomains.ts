// src/apps/admin/stores/useAdminDomains.ts

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import type { ColonelCustomDomain } from '@/schemas/api/internal/responses/colonel';
import { colonelCustomDomainsResponseSchema } from '@/schemas/api/internal/responses/colonel';
import { defineStore } from 'pinia';
import { ref } from 'vue';
import type { z } from 'zod';


type ColonelCustomDomainsResponse = z.infer<typeof colonelCustomDomainsResponseSchema>;

/**
 * Per-resource admin store for custom domains (CONTRACT 1 / #31).
 *
 * Sibling of {@link useAdminCustomers} — the shared paginated-fetch
 * composable makes a new resource a few lines pointing at its endpoint +
 * schema + selector. Backed by the existing `GET /api/colonel/domains`
 * and the existing `colonelCustomDomainsResponseSchema` (REUSED, no schema
 * changes — CONTRACT 3). Owns ONLY this resource's page state.
 *
 * Isolation: ZERO import edge into `src/apps/colonel/*` or
 * `src/shared/stores/colonelInfoStore.ts` (enforced by the architecture test),
 * so the legacy tree never enters the isolated admin bundle.
 */
export const useAdminDomains = defineStore('adminDomains', () => {
  /** Rows for the current page only (one server page — never accumulated). */
  const domains = ref<ColonelCustomDomain[]>([]);
  const pagination = ref<PageMeta | null>(null);

  const pager = usePaginatedFetch<ColonelCustomDomainsResponse, ColonelCustomDomain>({
    url: '/api/colonel/domains',
    schema: colonelCustomDomainsResponseSchema,
    context: 'CustomDomainsResponse',
    select: (data) => ({
      items: data.details?.domains ?? [],
      pagination: data.details?.pagination ?? null,
    }),
  });

  /**
   * Fetch one page of domains.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value
  ): Promise<{ items: ColonelCustomDomain[]; pagination: PageMeta | null } | null> {
    try {
      const result = await pager.fetchPage(targetPage);
      if (result) {
        domains.value = result.items;
        pagination.value = result.pagination;
      } else {
        domains.value = [];
        pagination.value = null;
      }
      return result;
    } catch (err) {
      domains.value = [];
      pagination.value = null;
      throw err;
    }
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    domains.value = [];
    pagination.value = null;
    pager.reset();
  }

  return {
    // State
    domains,
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
