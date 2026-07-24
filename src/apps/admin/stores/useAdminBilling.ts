// src/apps/admin/stores/useAdminBilling.ts

import {
  usePaginatedFetch,
  type PageMeta,
} from '@/apps/admin/composables/usePaginatedFetch';
import { createApiResponseSchema } from '@/schemas/api/base';
import { defineStore } from 'pinia';
import { computed, ref } from 'vue';
import { z } from 'zod';

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
 * Sibling of {@link useAdminOrganizations} / {@link useAdminCustomers} — same
 * `usePaginatedFetch` wiring, same two-failure-mode split (Zod mismatch degrades
 * to empty via `validationError`; network/HTTP sets `error` and throws).
 */

// ============================================================================
// Response contract
// ============================================================================
//
// TEMPORARY HOME. These schemas belong beside the rest of the billing contracts
// in `src/schemas/api/internal/responses/colonel-billing.ts`; they live here
// only because that file is owned by a concurrent change. See the handoff note
// in the PR — move them (re-exporting the types) once the endpoint lands.
//
// GET /api/colonel/billing/stripe-organizations → ListStripeOrganizations
//
// Every field except the two identity keys is `.nullish()` on purpose: the
// endpoint is landing concurrently, and a lenient row shape means a partial or
// still-evolving payload renders a degraded row rather than blanking the whole
// table through a `gracefulParse` failure.

/** One organization that has a Stripe customer id. */
export const colonelStripeOrganizationSchema = z.object({
  /** The organization's PUBLIC id — routes to /colonel/organizations/:id. */
  extid: z.string(),
  /** The Stripe customer id (`cus_…`) — the index field this list is keyed by. */
  stripe_customer_id: z.string(),
  org_id: z.string().nullish(),
  display_name: z.string().nullish(),
  owner_email: z.string().nullish(),
  billing_email: z.string().nullish(),
  planid: z.string().nullish(),
  stripe_subscription_id: z.string().nullish(),
  subscription_status: z.string().nullish(),
  subscription_period_end: z.string().nullish(),
  sync_status: z.string().nullish(),
});

/**
 * The canonical four-field pagination envelope ({@link PageMeta}) plus the two
 * bound signals this index-backed read carries:
 *
 * - `capped`      the HSCAN hit its entry bound, so `total_count` UNDERSTATES
 *                 the real population. Never render "showing X of Y" as exact.
 * - `stale_count` index entries on THIS page whose organization no longer
 *                 loads; they are dropped, so a page can be short.
 *
 * Both are optional: they are read wherever the adapter puts them (pagination
 * envelope or the details root — see {@link colonelStripeOrganizationsDetailsSchema}).
 */
const stripeOrganizationsPaginationSchema = z.object({
  page: z.number(),
  per_page: z.number(),
  total_count: z.number(),
  total_pages: z.number(),
  capped: z.boolean().optional(),
  stale_count: z.number().optional(),
});

export const colonelStripeOrganizationsDetailsSchema = z.object({
  organizations: z.array(colonelStripeOrganizationSchema),
  pagination: stripeOrganizationsPaginationSchema,
  /** Server echo of the applied filters. Optional — never read for state. */
  filters: z.object({ search: z.string().nullish() }).optional(),
  // Accepted at the details root too, since the HTTP adapter for this op is
  // landing concurrently and may hang the bound signals here instead.
  capped: z.boolean().optional(),
  stale_count: z.number().optional(),
});

export type StripeOrganizationsPageMeta = z.infer<typeof stripeOrganizationsPaginationSchema>;

export const colonelStripeOrganizationsResponseSchema = createApiResponseSchema(
  z.object({}),
  colonelStripeOrganizationsDetailsSchema
);

export type ColonelStripeOrganization = z.infer<typeof colonelStripeOrganizationSchema>;
export type ColonelStripeOrganizationsResponse = z.infer<
  typeof colonelStripeOrganizationsResponseSchema
>;

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
function selectPage(
  data: ColonelStripeOrganizationsResponse
): { items: ColonelStripeOrganization[]; pagination: StripeOrganizationsPageMeta | null } {
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
