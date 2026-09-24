// src/apps/admin/composables/useOrganizationsList.ts

import { usePaginatedFetch, type PageMeta } from '@/apps/admin/composables/usePaginatedFetch';
import type { ColonelOrganization } from '@/schemas/api/internal/responses/colonel';
import { colonelOrganizationsResponseSchema } from '@/schemas/api/internal/responses/colonel';
import { ref, type Ref } from 'vue';
import type { z } from 'zod';

type ColonelOrganizationsResponse = z.infer<typeof colonelOrganizationsResponseSchema>;

/** Server-side filters the `GET /api/colonel/organizations` endpoint honours. */
export interface OrganizationsListFilters {
  /** Subscription status: active / trialing / past_due / canceled. */
  status?: string;
  /** Billing sync health: synced / potentially_stale / unknown. */
  sync_status?: string;
  /**
   * Identifier lookup: matches an org by exact objid or extid, or by
   * case-insensitive substring of any contact/owner/billing email.
   */
  search?: string;
}

export interface UseOrganizationsList {
  /** Rows for the current page only (one server page — never accumulated). */
  organizations: Ref<ColonelOrganization[]>;
  pagination: Ref<PageMeta | null>;
  /**
   * Roster-cache state reported by the last successful response, or null when
   * the server sent none (a payload predating the block).
   */
  loading: Ref<boolean>;
  error: Ref<Error | null>;
  validationError: Ref<string | null>;
  page: Ref<number>;
  perPage: Ref<number>;
  fetchPage: (targetPage?: number, filters?: OrganizationsListFilters) => Promise<void>;
}

/**
 * List-side data source for the colonel Organizations screen.
 *
 * Talks to {@link usePaginatedFetch} directly: one server page per request,
 * with the three server-side filters forwarded as given. The endpoint has no
 * roster cache (its reads are bounded and index-backed), so there is no cache
 * block to surface and no bypass param to send. It is deliberately NOT a pinia
 * store — the list has exactly one consumer and no cross-view state to share.
 *
 * The two failure modes stay split exactly as the shared composable defines
 * them: a Zod mismatch degrades to an empty table (`validationError`), a
 * network/HTTP failure surfaces the banner + retry (`error`). `fetchPage` here
 * does NOT rethrow — the view's only response to a throw was to swallow it, and
 * `error` already drives the banner.
 */
export function useOrganizationsList(): UseOrganizationsList {
  const organizations = ref<ColonelOrganization[]>([]);
  const pagination = ref<PageMeta | null>(null);

  /**
   * Monotonic id of the newest fetchPage call. Responses settle out of order
   * when an operator changes search/filters/page while a request is in
   * flight; only the request that still matches this counter may commit
   * state, so a slower obsolete response can never replace the table with
   * rows from a query the visible controls no longer describe.
   */
  let requestSeq = 0;
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
   * @param filters optional server-side filters (empty values are dropped).
   *   The server has no roster cache: every read is a bounded, index-backed
   *   query, so a refresh is just another fetch of the same page.
   */
  async function fetchPage(
    targetPage: number = pager.page.value,
    filters: OrganizationsListFilters = {}
  ): Promise<void> {
    const requestId = ++requestSeq;
    try {
      const result = await pager.fetchPage(targetPage, {
        status: filters.status,
        sync_status: filters.sync_status,
        search: filters.search,
      });
      // Stale response: a newer fetchPage owns the state now — discard.
      if (requestId !== requestSeq) return;
      organizations.value = result?.items ?? [];
      pagination.value = result?.pagination ?? null;
    } catch {
      // Network/HTTP failure is captured in `error`; the view's banner + retry
      // handle it. Swallow so it doesn't become an unhandled rejection.
      if (requestId !== requestSeq) return;
      organizations.value = [];
      pagination.value = null;
    }
  }

  return {
    organizations,
    pagination,
    loading: pager.loading,
    error: pager.error,
    validationError: pager.validationError,
    page: pager.page,
    perPage: pager.perPage,
    fetchPage,
  };
}
