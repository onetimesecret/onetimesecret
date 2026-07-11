// src/apps/admin/stores/useAdminOrganizations.ts

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import type { ColonelOrganization } from '@/schemas/api/internal/responses/colonel';
import { colonelOrganizationsResponseSchema } from '@/schemas/api/internal/responses/colonel';
import { defineStore } from 'pinia';
import { ref } from 'vue';
import type { z } from 'zod';

type ColonelOrganizationsResponse = z.infer<typeof colonelOrganizationsResponseSchema>;

/** Server-side filters the `GET /api/colonel/organizations` endpoint honours. */
export interface OrganizationFilters {
  /** Subscription status: active / trialing / past_due / canceled. */
  status?: string;
  /** Billing sync health: synced / potentially_stale / unknown. */
  sync_status?: string;
  /**
   * Identifier lookup: matches an org by exact objid or extid, or by
   * case-insensitive substring of any contact/owner/billing email. Powers the
   * admin org-picker (attach-domain flow).
   */
  search?: string;
}

/**
 * Per-resource admin store for organizations (CONTRACT 1 / #32).
 *
 * Sibling of {@link useAdminCustomers} / {@link useAdminDomains} — the shared
 * paginated-fetch composable makes a new resource a few lines pointing at its
 * endpoint + schema + selector. Backed by the existing
 * `GET /api/colonel/organizations` and the existing
 * `colonelOrganizationsResponseSchema` (REUSED, no schema changes — CONTRACT 3).
 * Owns ONLY this resource's page state; the two server-side filters
 * (subscription `status` + billing `sync_status`) are threaded through as fetch
 * params, mirroring the legacy `ColonelOrganizations` screen's filter bar.
 *
 * Isolation: ZERO import edge into `src/apps/colonel/*` or
 * `src/shared/stores/colonelInfoStore.ts` (enforced by the architecture test),
 * so the legacy tree never enters the isolated admin bundle.
 */
export const useAdminOrganizations = defineStore('adminOrganizations', () => {
  /** Rows for the current page only (one server page — never accumulated). */
  const organizations = ref<ColonelOrganization[]>([]);
  const pagination = ref<PageMeta | null>(null);

  const pager = usePaginatedFetch<ColonelOrganizationsResponse, ColonelOrganization>({
    url: '/api/colonel/organizations',
    schema: colonelOrganizationsResponseSchema,
    context: 'ColonelOrganizationsResponse',
    select: (data) => ({
      items: data.details?.organizations ?? [],
      pagination: data.details?.pagination ?? null,
    }),
  });

  /**
   * Fetch one page of organizations.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @param filters optional subscription `status` + billing `sync_status` server
   *   filters (empty/undefined values are dropped by the composable).
   * @returns the page result, or null on a schema mismatch (see validationError).
   * @throws the underlying network/HTTP error (state is cleared first).
   */
  async function fetchPage(
    targetPage: number = pager.page.value,
    filters: OrganizationFilters = {}
  ): Promise<{ items: ColonelOrganization[]; pagination: PageMeta | null } | null> {
    try {
      const result = await pager.fetchPage(targetPage, {
        status: filters.status,
        sync_status: filters.sync_status,
        search: filters.search,
      });
      if (result) {
        organizations.value = result.items;
        pagination.value = result.pagination;
      } else {
        organizations.value = [];
        pagination.value = null;
      }
      return result;
    } catch (err) {
      organizations.value = [];
      pagination.value = null;
      throw err;
    }
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    organizations.value = [];
    pagination.value = null;
    pager.reset();
  }

  return {
    // State
    organizations,
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
