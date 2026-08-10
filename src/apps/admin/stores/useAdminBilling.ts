// src/apps/admin/stores/useAdminBilling.ts

import { usePaginatedFetch, type PageMeta } from '@/apps/admin/composables/usePaginatedFetch';
import {
  colonelStripeOrganizationSchema,
  colonelStripeOrganizationsDetailsSchema,
  colonelStripeOrganizationsResponseSchema,
  type ColonelStripeOrganization,
  type ColonelStripeOrganizationsResponse,
  type StripeOrganizationsPageMeta,
} from '@/schemas/api/internal/responses/colonel-billing';
import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

/**
 * Per-resource admin store for the billing screen's Stripe-customer roster.
 *
 * Scope is deliberately narrow: the catalog/drift read-out stays on
 * {@link useResourceFetch} inside the views (CONTRACT 1 — one-shot reads do not
 * get a store); this store owns ONLY the paginated, searchable list of
 * organizations that carry a `stripe_customer_id`, which is index-backed
 * server-side (`organization:stripe_customer_id_index`) and therefore pages like
 * every other admin list.
 *
 * Sibling of {@link useAdminCustomers} — same
 * `usePaginatedFetch` wiring, same two-failure-mode split (Zod mismatch degrades
 * to empty via `validationError`; network/HTTP sets `error` and throws).
 */

// ============================================================================
// Response contract
// ============================================================================
//
// GET /api/colonel/billing/stripe-organizations → ListStripeOrganizations,
// whose `SCHEMAS = { response: 'colonelStripeOrganizations' }` resolves through
// the registry to the schema imported below. The contract itself lives beside
// the other billing contracts in the schemas tree (the OpenAPI scanner asserts
// every declared SCHEMA constant resolves); it is re-exported here so existing
// consumers keep importing from the store.

export {
  colonelStripeOrganizationSchema,
  colonelStripeOrganizationsDetailsSchema,
  colonelStripeOrganizationsResponseSchema,
};

export type {
  ColonelStripeOrganization,
  ColonelStripeOrganizationsResponse,
  StripeOrganizationsPageMeta,
};

/** Server-side filters the endpoint honours. */
export interface StripeOrganizationFilters {
  /** Glob/substring over the Stripe customer id (HSCAN `matching:` server-side). */
  search?: string;
}

export const STRIPE_ORGANIZATIONS_URL = '/api/colonel/billing/stripe-organizations';

/** Narrow an unknown error to its HTTP status without importing axios types. */
function httpStatusOf(err: unknown): number | undefined {
  return (err as { response?: { status?: number } } | null)?.response?.status;
}

/**
 * Map the validated envelope onto the shared `{ items, pagination }` shape,
 * normalizing the bound signals (`capped` / `stale_count`) onto the pagination
 * object so the view reads them from ONE place regardless of where the HTTP
 * adapter chose to emit them.
 */
function selectPage(data: ColonelStripeOrganizationsResponse): {
  items: ColonelStripeOrganization[];
  pagination: StripeOrganizationsPageMeta | null;
} {
  const meta = data.details?.pagination ?? null;
  return {
    items: data.details?.organizations ?? [],
    pagination: meta
      ? {
          ...meta,
          capped: meta.capped ?? data.details?.capped,
          stale_count: meta.stale_count ?? data.details?.stale_count,
        }
      : null,
  };
}

export const useAdminBilling = defineStore('adminBilling', () => {
  /** Rows for the current page only (one server page — never accumulated). */
  const stripeOrganizations = ref<ColonelStripeOrganization[]>([]);
  const pagination = ref<StripeOrganizationsPageMeta | null>(null);

  /**
   * True when the server's bounded index scan hit its limit — `total_count` is
   * then a floor, not the population. Read from wherever the adapter puts it.
   */
  const capped = ref(false);
  /** Index entries on the current page whose organization no longer loads. */
  const staleCount = ref(0);

  /**
   * True when the endpoint answered 404 — i.e. this build of the frontend is
   * running against a backend that does not serve the roster yet. Held apart
   * from `error` so the section renders an informational "not available" notice
   * instead of a red failure banner an operator would try to retry forever.
   */
  const unavailable = ref(false);

  const pager = usePaginatedFetch<ColonelStripeOrganizationsResponse, ColonelStripeOrganization>({
    url: STRIPE_ORGANIZATIONS_URL,
    schema: colonelStripeOrganizationsResponseSchema,
    context: 'ColonelStripeOrganizationsResponse',
    select: selectPage,
  });

  /** Adopt (or clear) one page of rows plus its bound signals. */
  function adopt(
    result: { items: ColonelStripeOrganization[]; pagination: PageMeta | null } | null
  ): void {
    stripeOrganizations.value = result?.items ?? [];
    pagination.value = result?.pagination ?? null;
    capped.value = pagination.value?.capped === true;
    staleCount.value = pagination.value?.stale_count ?? 0;
  }

  /** Suppress the failure banner for the "endpoint not deployed yet" case. */
  const error = computed(() => (unavailable.value ? null : pager.error.value));

  /**
   * Fetch one page of Stripe-linked organizations.
   *
   * @param targetPage 1-based page (defaults to the current page).
   * @param filters optional `search` over the Stripe customer id.
   * @returns the page result, or null on a schema mismatch / missing endpoint.
   * @throws the underlying network/HTTP error, EXCEPT a 404 (see `unavailable`).
   */
  async function fetchStripeOrganizations(
    targetPage: number = pager.page.value,
    filters: StripeOrganizationFilters = {}
  ): Promise<{ items: ColonelStripeOrganization[]; pagination: PageMeta | null } | null> {
    unavailable.value = false;
    try {
      // A null result is a schema mismatch: degrade to empty, and
      // pager.validationError names the contract that drifted.
      const result = await pager.fetchPage(targetPage, { search: filters.search });
      adopt(result);
      return result;
    } catch (err) {
      adopt(null);
      if (httpStatusOf(err) === 404) {
        unavailable.value = true;
        return null;
      }
      throw err;
    }
  }

  /** Explicit manual reset — setup stores have no built-in $reset. */
  function $reset(): void {
    adopt(null);
    unavailable.value = false;
    pager.reset();
  }

  return {
    // State
    stripeOrganizations,
    pagination,
    unavailable,
    capped,
    staleCount,
    // Fetch state (owned by the shared composable)
    loading: pager.loading,
    error,
    validationError: pager.validationError,
    page: pager.page,
    perPage: pager.perPage,
    // Actions
    fetchStripeOrganizations,
    $reset,
  };
});
