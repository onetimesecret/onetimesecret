// src/apps/admin/composables/useResourceFetch.ts

import type { ZodType } from 'zod';
import { ref, type Ref } from 'vue';

import { useApi } from '@/shared/composables/useApi';
import { gracefulParse } from '@/utils/schemaValidation';

/** Query params for a single-resource GET (filters, expansions, …). */
export type ResourceFetchParams = Record<string, string | number | boolean | undefined | null>;

/**
 * Schema-aware single-resource fetch contract (CONTRACT 2 — the sibling of
 * {@link usePaginatedFetch} for one GET of one record). A detail view supplies:
 * - `url`     the endpoint. A getter is allowed so the id can be read lazily
 *             (vue-router reuses a detail component across param changes).
 * - `schema`  the wrapped Zod response schema (createApiResponseSchema output).
 * - `context` a label handed to gracefulParse and surfaced as `validationError`.
 */
export interface ResourceFetchConfig<TResponse> {
  url: string | (() => string);
  schema: ZodType<TResponse>;
  context: string;
}

export interface UseResourceFetch<TResponse> {
  /** The validated response (the whole `{ record, details }` envelope), or null. */
  data: Ref<TResponse | null>;
  /** True while a request is in flight. Owned here so views never track it. */
  loading: Ref<boolean>;
  /** The last thrown network/HTTP error, or null. Set only on a real failure. */
  error: Ref<Error | null>;
  /**
   * The `context` label when the payload failed Zod validation, else null. Kept
   * SEPARATE from `error` so a view can distinguish "the response didn't match
   * the contract" (degrade) from "the request threw" (network/http — retry).
   */
  validationError: Ref<string | null>;
  /**
   * True when the last request failed with HTTP 404. Broken out from `error` so
   * every detail screen can render a first-class not-found state (the record was
   * purged / the id is wrong) instead of a generic failure. Reset on each load.
   */
  notFound: Ref<boolean>;
  /** Fetch the resource once. Resolves the validated data, or null on mismatch. */
  load: (params?: ResourceFetchParams) => Promise<TResponse | null>;
  /** Re-run the last {@link load} (same url + params). */
  refresh: () => Promise<TResponse | null>;
  /** Restore initial state (clears data + all flags). */
  reset: () => void;
}

/** Narrow an unknown error to its HTTP status without importing axios types. */
function httpStatusOf(err: unknown): number | undefined {
  return (err as { response?: { status?: number } } | null)?.response?.status;
}

/**
 * Shared single-resource fetch composable for the admin console (CONTRACT 2).
 *
 * The GET analogue of {@link usePaginatedFetch}: it owns `loading`, holds the
 * validated record, and splits the two failure modes a detail view handles
 * differently:
 *
 *   - Zod validation mismatch → resolves `null`, sets `validationError`,
 *                               does NOT throw (the view degrades gracefully).
 *   - Network / HTTP error    → sets `error` (+ `notFound` on 404) and THROWS.
 *
 * Built on the injected Axios `$api` (via {@link useApi}) and the existing
 * {@link gracefulParse} helper — no new HTTP client, no schema changes. This is
 * the TEMPLATE the 30/31/32 detail views copy: point it at an endpoint + a
 * `createApiResponseSchema` output and read `data.value?.record` / `.details`.
 */
export function useResourceFetch<TResponse>(
  config: ResourceFetchConfig<TResponse>
): UseResourceFetch<TResponse> {
  const $api = useApi();

  const data = ref<TResponse | null>(null) as Ref<TResponse | null>;
  const loading = ref(false);
  const error = ref<Error | null>(null);
  const validationError = ref<string | null>(null);
  const notFound = ref(false);

  // Remember the last params so `refresh()` re-issues an identical request.
  let lastParams: ResourceFetchParams | undefined;

  function resolveUrl(): string {
    return typeof config.url === 'function' ? config.url() : config.url;
  }

  async function load(params?: ResourceFetchParams): Promise<TResponse | null> {
    lastParams = params;
    loading.value = true;
    error.value = null;
    validationError.value = null;
    notFound.value = false;

    try {
      const response = await $api.get(resolveUrl(), params ? { params } : undefined);
      const result = gracefulParse(config.schema, response.data, config.context);
      if (!result.ok) {
        // Contract mismatch: degrade quietly. gracefulParse already reported it.
        validationError.value = config.context;
        data.value = null;
        return null;
      }

      data.value = result.data;
      return result.data;
    } catch (err) {
      notFound.value = httpStatusOf(err) === 404;
      error.value = err instanceof Error ? err : new Error(String(err));
      data.value = null;
      throw error.value;
    } finally {
      loading.value = false;
    }
  }

  function refresh(): Promise<TResponse | null> {
    return load(lastParams);
  }

  function reset(): void {
    data.value = null;
    loading.value = false;
    error.value = null;
    validationError.value = null;
    notFound.value = false;
    lastParams = undefined;
  }

  return { data, loading, error, validationError, notFound, load, refresh, reset };
}
