// src/apps/admin/stores/useAdminSecrets.ts

import { defineStore } from 'pinia';
import type { z } from 'zod';
import { ref } from 'vue';

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import { colonelSecretsResponseSchema } from '@/schemas/api/internal/responses/colonel';
import type { ColonelSecret } from '@/schemas/api/account/responses/colonel';

type ColonelSecretsResponse = z.infer<typeof colonelSecretsResponseSchema>;

/**
 * Per-resource admin store for secrets (CONTRACT 3).
 *
 * Sibling of {@link useAdminCustomers}, proving the shared composable's payoff:
 * a new resource is a few lines pointing at its endpoint + schema + selector.
 * Backed by the existing `GET /api/colonel/secrets` and the existing
 * `colonelSecretsResponseSchema` (no endpoint or schema changes). ZERO import
 * edge into `src/apps/colonel/*` or `colonelInfoStore.ts`.
 */
export const useAdminSecrets = defineStore('adminSecrets', () => {
  /** Rows for the current page only (one server page — never accumulated). */
  const secrets = ref<ColonelSecret[]>([]);
  const pagination = ref<PageMeta | null>(null);

  const pager = usePaginatedFetch<ColonelSecretsResponse, ColonelSecret>({
    url: '/api/colonel/secrets',
    schema: colonelSecretsResponseSchema,
    context: 'ColonelSecretsResponse',
    select: (data) => ({
      items: data.details?.secrets ?? [],
      pagination: data.details?.pagination ?? null,
    }),
  });

  /**
   * Fetch one page of secrets.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value
  ): Promise<{ items: ColonelSecret[]; pagination: PageMeta | null } | null> {
    try {
      const result = await pager.fetchPage(targetPage);
      if (result) {
        secrets.value = result.items;
        pagination.value = result.pagination;
      } else {
        secrets.value = [];
        pagination.value = null;
      }
      return result;
    } catch (err) {
      secrets.value = [];
      pagination.value = null;
      throw err;
    }
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    secrets.value = [];
    pagination.value = null;
    pager.reset();
  }

  return {
    // State
    secrets,
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
