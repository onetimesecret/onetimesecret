// src/apps/admin/stores/useAdminDomainToolbox.ts

import { defineStore } from 'pinia';
import type { z } from 'zod';
import { ref } from 'vue';

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import { colonelDomainsOrphanedResponseSchema } from '@/schemas/api/internal/responses/colonel-domaintoolbox';
import type { ColonelOrphanedDomain } from '@/schemas/api/internal/responses/colonel-domaintoolbox';

type ColonelDomainsOrphanedResponse = z.infer<typeof colonelDomainsOrphanedResponseSchema>;

/**
 * Per-resource admin store for the Domain Toolbox's orphaned-domains scan
 * (ticket #43, CONTRACT 3). Sibling of {@link useAdminSessions}: one server page
 * per request over the NEW `GET /api/colonel/domains/orphaned` endpoint (a thin
 * adapter over `Onetime::Operations::Domains::OrphanedScan` — bounded scan of the
 * CustomDomain instances set, #2211, NOT a blocking KEYS).
 *
 * READ-ONLY: the scan mutates nothing. ZERO import edge into `src/apps/colonel/*`
 * or `colonelInfoStore.ts` (CONTRACT 7).
 */
export const useAdminDomainToolbox = defineStore('adminDomainToolbox', () => {
  /** Orphaned rows for the current page only (never accumulated). */
  const orphaned = ref<ColonelOrphanedDomain[]>([]);
  const pagination = ref<PageMeta | null>(null);

  const pager = usePaginatedFetch<ColonelDomainsOrphanedResponse, ColonelOrphanedDomain>({
    url: '/api/colonel/domains/orphaned',
    schema: colonelDomainsOrphanedResponseSchema,
    context: 'ColonelDomainsOrphanedResponse',
    select: (data) => ({
      items: data.details?.domains ?? [],
      pagination: data.details?.pagination ?? null,
    }),
  });

  /**
   * Fetch one page of orphaned domains.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value
  ): Promise<{ items: ColonelOrphanedDomain[]; pagination: PageMeta | null } | null> {
    try {
      const result = await pager.fetchPage(targetPage);
      if (result) {
        orphaned.value = result.items;
        pagination.value = result.pagination;
      } else {
        orphaned.value = [];
        pagination.value = null;
      }
      return result;
    } catch (err) {
      orphaned.value = [];
      pagination.value = null;
      throw err;
    }
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    orphaned.value = [];
    pagination.value = null;
    pager.reset();
  }

  return {
    // State
    orphaned,
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
