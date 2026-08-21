// src/plugins/axios/interceptors.ts

import { scrubSensitiveStrings, scrubUrlWithPatterns } from '@/utils/diagnostics/scrubbers';
import { useLanguageStore } from '@/shared/stores';
import { setCurrentApiRoute } from '@/utils/diagnostics/apiRouteContext';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { addBreadcrumb } from '@sentry/vue';
import type { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from 'axios';

/**
 * CSRF Token Interceptors
 *
 * Manages CSRF (Cross-Site Request Forgery) tokens using Rack::Protection.
 *
 * Key Features:
 * - Automatic token management in X-CSRF-Token header
 * - Token validation and updates from server responses
 * - Error handling with token preservation
 *
 * Flow:
 * 1. Request: Attaches current token to X-CSRF-Token header
 * 2. Response: Updates token from X-CSRF-Token response header
 * 3. Error: Preserves token updates even in error cases
 *
 * The token is stored in session[:csrf] by Rack::Protection::AuthenticityToken middleware.
 */

/**
 * Validates if a given value is a valid shrimp token
 * @param shrimp - The value to validate
 * @returns boolean indicating if the value is a valid string token
 */
const isValidShrimp = (shrimp: unknown): shrimp is string =>
  typeof shrimp === 'string' && shrimp.length > 0;

/**
 * Domain Context Override header name.
 * Used for persona-based testing in development mode.
 */
const DOMAIN_CONTEXT_HEADER = 'O-Domain-Context';
const DOMAIN_CONTEXT_STORAGE_KEY = 'domainContext';

/**
 * Gets the domain context override from sessionStorage.
 * @returns The domain context value or null if not set
 */
const getDomainContext = (): string | null => {
  try {
    return sessionStorage.getItem(DOMAIN_CONTEXT_STORAGE_KEY);
  } catch {
    // sessionStorage may not be available (SSR, private browsing, etc.)
    return null;
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// API-ROUTE SLOT LIFECYCLE
// ─────────────────────────────────────────────────────────────────────────────
//
// `setCurrentApiRoute` fills a single module-level slot that `resolveApiRoute()`
// reads whenever a schema validation fails, to tag the event with the endpoint
// that produced the payload. Stamping it on request and NEVER clearing it made
// the slot monotonic: after the first API call of the session, every later
// `gracefulParse` failure — including ones with no axios call behind them at
// all (the bootstrap payload parsed at startup, a sessionStorage bag re-read on
// a user action) — was tagged with whatever route happened to go out last.
//
// Misattribution, not disclosure: the value stored here is parameterized on the
// way in (`/api/colonel/orgs/:org_id`) and scrubbed again by `sanitizeApiRoute`
// on the way out, so the stale route was a route either way — see the
// guaranteed/best-effort split in `apiRouteContext.ts` for how far that goes.
// It is a CORRECTNESS defect in a diagnostic, which has its own cost:
// `apiRoute` is the field an operator uses to decide which endpoint to go read,
// and a confidently wrong one sends them to code that never ran.
//
// TWO THINGS MAKE THE RELEASE CORRECT, and both are load-bearing:
//
//  1. IT IS DEFERRED BY A MACROTASK. The consumer of the slot is not this
//     module — it is the awaiting caller, which runs `gracefulParse` on the
//     response body in a microtask continuation queued AFTER the response
//     interceptor returns. Clearing synchronously here would delete the route
//     just before the one parse that needs it, turning a wrong tag into no tag.
//     A `setTimeout(…, 0)` callback runs after the entire microtask queue
//     drains, so the caller's response handling still resolves the route and
//     anything later does not.
//
//  2. IT IS REFERENCE-COUNTED. Requests overlap. The slot is last-writer-wins
//     by design, but an unconditional clear on settle would let a short request
//     A wipe the route of a slower in-flight request B. Clearing only when the
//     count reaches zero means an overlap degrades to the pre-existing
//     last-writer-wins behaviour rather than to an empty slot.
//
// A request whose promise never settles (a page unload mid-flight) leaves the
// count above zero and the slot stamped — i.e. exactly today's behaviour, which
// is the right failure direction for a change whose whole purpose is to not
// lose diagnostics.

let inFlightRequests = 0;
let pendingSlotClear: ReturnType<typeof setTimeout> | null = null;

/** Stamps the outgoing route and takes a reference on the slot. */
const noteApiRequestStarted = (url: string | null): void => {
  inFlightRequests += 1;
  setCurrentApiRoute(url);
};

/**
 * Drops a reference and, once nothing is in flight, clears the slot one
 * macrotask later. Safe to call more times than `noteApiRequestStarted` — the
 * count floors at zero rather than going negative.
 */
const releaseApiRouteSlot = (): void => {
  inFlightRequests = Math.max(0, inFlightRequests - 1);
  if (inFlightRequests > 0 || pendingSlotClear !== null) return;
  pendingSlotClear = setTimeout(() => {
    pendingSlotClear = null;
    // Re-checked: a new request may have started while this was queued.
    if (inFlightRequests === 0) setCurrentApiRoute(null);
  }, 0);
};

/**
 * Drops the in-flight count and any queued clear. TEST-CLEANUP HELPER, mirroring
 * `resetApiRouteContext()` in the module that owns the slot itself: a spec that
 * drives `requestInterceptor` without a matching settle would otherwise carry a
 * non-zero reference count into the next test and suppress its clear.
 */
export const resetApiRouteSlotLifecycle = (): void => {
  inFlightRequests = 0;
  if (pendingSlotClear !== null) {
    clearTimeout(pendingSlotClear);
    pendingSlotClear = null;
  }
};

/**
 * Request interceptor that adds the CSRF token to outgoing requests
 * @param config - Axios request configuration
 * @returns Modified config with CSRF token in headers
 */
export const requestInterceptor = (config: InternalAxiosRequestConfig) => {
  config.headers = config.headers || {};

  // Stamp the PARAMETERIZED route of the call now going out, so that a schema
  // -validation failure on its response can say WHICH ENDPOINT produced the
  // payload without naming the tenant.
  //
  // This is the single production caller of `setCurrentApiRoute`, and the whole
  // of requirement 6 hangs off it: without this line `resolveApiRoute()` returns
  // `undefined` forever and the `apiRoute` tag never exists. It lives here
  // because the request interceptor is the ONE place in the app that holds a
  // request URL — `gracefulParse`'s ~25 call sites receive a decoded body and
  // nothing else.
  //
  // The URL is parameterized ON THE WAY IN (`setCurrentApiRoute` calls
  // `parameterizeApiPath` before storing), so the resolved form is never
  // retained even in memory, and the slot holds at most one short string.
  //
  // Stamped BEFORE the store reads below, which sit inside a try/catch that
  // swallows a pre-Pinia bootstrap failure: the route must be recorded whether
  // or not the stores are available.
  //
  // The slot is RELEASED again when the request settles — see
  // `releaseApiRouteSlot`. Leaving it stamped forever was a misattribution bug,
  // not a leak.
  noteApiRequestStarted(config.url ?? null);

  // Access all Pinia stores in a single try/catch block.
  // Pinia throws if called before app.use(pinia) during bootstrap.
  try {
    const csrfStore = useCsrfStore();
    const languageStore = useLanguageStore();
    const organizationStore = useOrganizationStore();

    // Set CSRF token (Rack::Protection::JsonCsrf expects X-CSRF-Token)
    config.headers['X-CSRF-Token'] = csrfStore.shrimp;
    config.headers['Accept-Language'] = languageStore.getCurrentLocale;

    // Sync frontend org selection to backend on every request
    if (organizationStore.currentOrganization?.objid) {
      config.headers['O-Organization-ID'] = organizationStore.currentOrganization.objid;
    }
  } catch {
    // Pinia not yet active during app bootstrap — request proceeds without store headers
  }

  // Add domain context override header if set (development feature)
  const domainContext = getDomainContext();
  if (domainContext) {
    config.headers[DOMAIN_CONTEXT_HEADER] = domainContext;
  }

  // For FormData uploads, delete Content-Type so Axios sets it with the boundary
  if (config.data instanceof FormData) {
    delete config.headers['Content-Type'];
  }

  return config;
};

/**
 * Response interceptor that handles successful responses and token updates
 * @param response - Axios response object
 * @returns The original response after processing
 */
export const responseInterceptor = (response: AxiosResponse) => {
  // First, so the reference is dropped even if a store read below throws.
  releaseApiRouteSlot();

  const csrfStore = useCsrfStore();
  // Read CSRF token from response header (industry standard)
  const responseShrimp = response.headers['x-csrf-token'];

  if (isValidShrimp(responseShrimp)) {
    csrfStore.updateShrimp(responseShrimp);
  }

  return response;
};

/**
 * Error interceptor that handles failed requests while preserving token updates
 * @param error - Axios error object
 * @returns Rejected promise with simplified error message
 */
export const errorInterceptor = (error: AxiosError) => {
  // First, so the reference is dropped even if a store read below throws. A
  // failed request settles the same as a successful one; the caller's catch
  // block still resolves the route for the macrotask that follows.
  releaseApiRouteSlot();

  const csrfStore = useCsrfStore();
  // Read CSRF token from response header even in error cases
  const responseShrimp = error.response?.headers['x-csrf-token'];

  // Add Sentry breadcrumb for API debugging (#2965)
  // Scrub sensitive data from URL and error message before sending
  // Note: This complements breadcrumbsIntegration auto-capture (category 'xhr'/'fetch')
  // by adding error-specific context (reason) under a distinct 'axios' category.
  // The method/url in data object aligns with Sentry's http breadcrumb schema.
  const method = error.config?.method?.toUpperCase() ?? 'UNKNOWN';
  const url = error.config?.url ? scrubUrlWithPatterns(error.config.url) : 'unknown';
  addBreadcrumb({
    type: 'http',
    category: 'axios',
    level: 'error',
    message: `${method} ${url}`,
    data: {
      method,
      url,
      ...(error.response?.status != null && { status_code: error.response.status }),
      reason: scrubSensitiveStrings(error.message),
    },
  });

  // Update our local shrimp token if new one is provided
  if (isValidShrimp(responseShrimp)) {
    csrfStore.updateShrimp(responseShrimp);
  }

  return Promise.reject(error); // no gate keeping, just pass the error along
};

/**
 * Creates a truncated version of the shrimp token for safe logging
 * @param shrimp - The token to process
 * @returns A truncated version of the token (first 4 chars + "...")
 */
export const createLoggableShrimp = (shrimp: unknown): string => {
  if (!isValidShrimp(shrimp)) {
    return '';
  }
  return `${shrimp.slice(0, 4)}...`;
};
