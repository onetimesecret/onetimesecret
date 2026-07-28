// src/apps/admin/composables/useOrganizationsList.ts

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import type {
  ColonelOrganization,
  ColonelOrganizationsCache,
} from '@/schemas/api/internal/responses/colonel';
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
  cacheMeta: Ref<ColonelOrganizationsCache | null>;
  loading: Ref<boolean>;
  error: Ref<Error | null>;
  validationError: Ref<string | null>;
  page: Ref<number>;
  perPage: Ref<number>;
  fetchPage: (
    targetPage?: number,
    filters?: OrganizationsListFilters,
    options?: { refresh?: boolean }
  ) => Promise<void>;
}

/**
 * List-side data source for the colonel Organizations screen.
 *
 * This replaced an `adminOrganizations` pinia store, whose `select` narrowed the
 * response to `{ items, pagination }` and whose `fetchPage` forwarded a fixed
 * three-filter set — so neither the roster-cache block on `details.cache` nor
 * the `refresh` cache-bypass param could reach the view through it. This
 * composable talks to {@link usePaginatedFetch} directly and keeps both. It is
 * deliberately NOT a pinia store — the list has exactly one consumer and no
 * cross-view state to share.
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
  const cacheMeta = ref<ColonelOrganizationsCache | null>(null);

  const pager = usePaginatedFetch<ColonelOrganizationsResponse, ColonelOrganization>({
    url: '/api/colonel/organizations',
    schema: colonelOrganizationsResponseSchema,
    context: 'ColonelOrganizationsResponse',
    select: (data) => {
      // `select` is the only place the validated response is in scope, and the
      // shared PageResult contract carries just items + pagination. Capturing
      // the cache block here keeps that contract frozen (it is shared with every
      // other admin list) instead of widening it for one screen.
      cacheMeta.value = data.details?.cache ?? null;
      return {
        items: data.details?.organizations ?? [],
        pagination: data.details?.pagination ?? null,
      };
    },
  });

  /**
   * Fetch one page of organizations.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @param filters optional server-side filters (empty values are dropped).
   * @param options.refresh when true, sends `refresh=1` so the server skips the
   *   roster cache and rebuilds it. Used by the header's refresh control — an
   *   operator who just reconciled an org must not be served the pre-mutation
   *   roster.
   */
  async function fetchPage(
    targetPage: number = pager.page.value,
    filters: OrganizationsListFilters = {},
    options: { refresh?: boolean } = {}
  ): Promise<void> {
    try {
      const result = await pager.fetchPage(targetPage, {
        status: filters.status,
        sync_status: filters.sync_status,
        search: filters.search,
        // Omitted entirely unless bypassing — `buildParams` drops undefined.
        refresh: options.refresh ? '1' : undefined,
      });
      organizations.value = result?.items ?? [];
      pagination.value = result?.pagination ?? null;
      if (!result) cacheMeta.value = null;
    } catch {
      // Network/HTTP failure is captured in `error`; the view's banner + retry
      // handle it. Swallow so it doesn't become an unhandled rejection.
      organizations.value = [];
      pagination.value = null;
      cacheMeta.value = null;
    }
  }

  return {
    organizations,
    pagination,
    cacheMeta,
    loading: pager.loading,
    error: pager.error,
    validationError: pager.validationError,
    page: pager.page,
    perPage: pager.perPage,
    fetchPage,
  };
}
