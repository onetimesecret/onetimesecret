// src/apps/admin/composables/usePaginatedFetch.ts

import type { ZodType } from 'zod';
import { ref, type Ref } from 'vue';

import { useApi } from '@/shared/composables/useApi';
import { gracefulParse } from '@/utils/schemaValidation';

import { noteAdminSessionExpiry } from '../utils/adminSessionExpiry';

/**
 * Canonical pagination envelope every admin list endpoint returns.
 *
 * These are the four fields frozen by the kit pagination control's emit
 * contract (page / per_page / total_count / total_pages). The colonel
 * `Pagination` type is structurally a superset (it also carries an optional
 * `role_filter`), so a resource's `select` may hand its own pagination object
 * straight through without a manual re-map.
 */
export interface PageMeta {
  page: number;
  per_page: number;
  total_count: number;
  total_pages: number;
  /**
   * True when a bounded server-side scan/window stopped early, making
   * total_count a FLOOR rather than the population. Optional — only the
   * endpoints with bounded filter scans (domains, users, billing) emit it;
   * views should render a caveat when it is true.
   */
  capped?: boolean;
}

/**
 * The one-page result a resource store cares about: the rows for THIS page plus
 * the server's pagination envelope. Deliberately narrow — the composable never
 * accumulates across pages, so it maps cleanly onto index-backed (ZRANGE)
 * server pagination instead of load-all-then-slice on the client.
 */
export interface PageResult<TItem> {
  items: TItem[];
  pagination: PageMeta | null;
}

/**
 * Schema-aware fetch contract (frozen — CONTRACT 2). A resource store supplies:
 * - `url`     the server endpoint (one server page per request)
 * - `schema`  the wrapped Zod response schema (createApiResponseSchema output)
 * - `context` a label handed to gracefulParse and surfaced as `validationError`
 * - `select`  maps the validated response onto the shared `{ items, pagination }`
 */
export interface PaginatedFetchConfig<TResponse, TItem> {
  url: string;
  schema: ZodType<TResponse>;
  context: string;
  select: (data: TResponse) => PageResult<TItem>;
  /** Initial/reset page size. Defaults to {@link DEFAULT_PER_PAGE}. */
  perPage?: number;
}

/** Query params passed alongside page/per_page (filters, or a future cursor). */
export type FetchParams = Record<string, string | number | boolean | undefined | null>;

export interface UsePaginatedFetch<TItem> {
  /** True while a request is in flight. Owned here so stores never track it. */
  loading: Ref<boolean>;
  /** The last thrown network/HTTP error, or null. Set only on a real failure. */
  error: Ref<Error | null>;
  /**
   * The `context` label when the server payload failed Zod validation, else
   * null. Kept SEPARATE from `error` so a view can distinguish "the response
   * didn't match the contract" (degrade to empty) from "the request threw"
   * (network/http — surface + retry).
   */
  validationError: Ref<string | null>;
  /** Current page (1-based). Reconciled to the server's echoed page on success. */
  page: Ref<number>;
  /** Current page size. Reconciled to the server's echoed per_page on success. */
  perPage: Ref<number>;
  fetchPage: (targetPage?: number, params?: FetchParams) => Promise<PageResult<TItem> | null>;
  reset: () => void;
}

/** Default rows per page, matching the legacy colonel list default. */
export const DEFAULT_PER_PAGE = 50;

/**
 * Shared paginated-fetch composable for the admin console (CONTRACT 2).
 *
 * Owns loading + page/perPage state, fetches exactly ONE server page, and
 * splits the two failure modes every resource store must handle differently:
 *
 *   - Zod validation mismatch  → resolves `null`, sets `validationError`,
 *                                does NOT throw (the store degrades to empty).
 *   - Network / HTTP error     → sets `error` and THROWS (the view handles it).
 *
 * Built on the injected Axios `$api` (via {@link useApi}) and the existing
 * {@link gracefulParse} helper — no new HTTP client, no schema changes.
 *
 * Cursor-readiness: request params are assembled in one place ({@link buildParams})
 * and the returned page is whatever the server sent, so swapping offset paging
 * for a `cursor` param later (per #20's index-backed endpoints) touches only
 * the param builder and the caller's `params` — not the store or view.
 */
export function usePaginatedFetch<TResponse, TItem>(
  config: PaginatedFetchConfig<TResponse, TItem>
): UsePaginatedFetch<TItem> {
  const $api = useApi();
  const defaultPerPage = config.perPage ?? DEFAULT_PER_PAGE;

  const loading = ref(false);
  const error = ref<Error | null>(null);
  const validationError = ref<string | null>(null);
  const page = ref(1);
  const perPage = ref(defaultPerPage);

  /**
   * Monotonic id of the newest fetchPage call. Overlapping requests settle in
   * arbitrary order; only the newest may touch the refs above, so a slower
   * obsolete response can never reconcile `page`/`perPage` (or clear
   * `loading`, or plant its error) out from under the request that replaced
   * it. The RETURN VALUE is not gated — each caller still receives its own
   * result and owns the same guard for any resource state it keeps (see
   * useOrganizationsList).
   */
  let requestSeq = 0;

  type QueryParams = Record<string, string | number | boolean>;

  /** Assemble the query for one server page. Empty/nullish extras are dropped. */
  function buildParams(targetPage: number, extra?: FetchParams): QueryParams {
    const params: QueryParams = {
      page: targetPage,
      per_page: perPage.value,
    };
    if (extra) {
      for (const [key, value] of Object.entries(extra)) {
        if (value !== undefined && value !== null && value !== '') {
          params[key] = value;
        }
      }
    }
    return params;
  }

  async function fetchPage(
    targetPage: number = page.value,
    params?: FetchParams
  ): Promise<PageResult<TItem> | null> {
    const requestId = ++requestSeq;
    loading.value = true;
    error.value = null;
    validationError.value = null;
    page.value = targetPage;

    try {
      const response = await $api.get(config.url, { params: buildParams(targetPage, params) });
      const result = gracefulParse(config.schema, response.data, config.context);
      if (!result.ok) {
        // Contract mismatch: degrade quietly. gracefulParse already reported it.
        if (requestId === requestSeq) validationError.value = config.context;
        return null;
      }

      const selected = config.select(result.data);
      if (requestId === requestSeq && selected.pagination) {
        page.value = selected.pagination.page;
        perPage.value = selected.pagination.per_page;
      }
      return selected;
    } catch (err) {
      const wrapped = err instanceof Error ? err : new Error(String(err));
      // Raised even for a superseded request: an expired admin window (#4331)
      // is a property of the session, not of this one fetch, and every later
      // request would fail the same way.
      noteAdminSessionExpiry(err);
      if (requestId === requestSeq) error.value = wrapped;
      throw wrapped;
    } finally {
      // A stale settle must not flip loading off while the newer request is
      // still in flight — only the newest request releases the flag.
      if (requestId === requestSeq) loading.value = false;
    }
  }

  /** Restore initial fetch state. Resource state is the store's responsibility.
   *  Also invalidates any in-flight request so its late settle cannot
   *  reconcile state over the freshly reset values. */
  function reset(): void {
    requestSeq++;
    loading.value = false;
    error.value = null;
    validationError.value = null;
    page.value = 1;
    perPage.value = defaultPerPage;
  }

  return { loading, error, validationError, page, perPage, fetchPage, reset };
}
