// src/utils/telemetry/apiRouteContext.ts
//
// ===========================================================================
// PARAMETERIZED API-ROUTE CONTEXT for schema-validation telemetry.
// ===========================================================================
//
// THE PROBLEM
// -----------
// A schema-validation failure is far easier to triage when the event says
// WHICH ENDPOINT produced the payload. But the resolved URL is exactly the
// thing we must not send:
//
//     /api/colonel/organizations/org_9f3a2b1c8d7e6f50    <- identifies a tenant
//     /api/colonel/organizations/:org_id                 <- identifies a route
//
// The second is strictly more useful for aggregation (all failures on that
// endpoint group into one issue) and carries no tenant reference at all. So the
// rule for every telemetry surface - tags, extras, exception messages,
// breadcrumbs, transaction names - is: PARAMETERIZED ROUTE, never resolved URL.
// `createDiagnostics` already enforces this for `event.transaction` by stamping
// `to.matched.at(-1)?.path` from the Vue router; this module is the API-side
// counterpart.
//
// WHY A RESOLVER HOOK AND NOT A NEW ARGUMENT
// ------------------------------------------
// `gracefulParse(schema, data, context)` is called from ~25 store/view sites.
// Threading a route argument through all of them would be a large, error-prone
// diff whose failure mode is silent (a missed site simply reports nothing), and
// most of those call sites do not have the URL in hand anyway - they receive a
// response body from a fetch helper.
//
// The URL IS in hand in exactly one place: the axios request interceptor. So
// this module keeps a single module-level slot that the interceptor stamps, and
// `gracefulParse` reads. That wiring is LIVE: `requestInterceptor` in
// `src/plugins/axios/interceptors.ts` stamps the slot on every outbound request
// (via `noteApiRequestStarted(config.url ?? null)`, which calls
// `setCurrentApiRoute`) and releases it one macrotask after the last in-flight
// request settles. So `apiRoute` is a populated, INDEXED dimension on real
// events - specifically a TAG, see `TAG_FIELDS` in
// `src/services/diagnostics.service.ts` - not a dormant code path. The resolver
// default is still the no-op, which is what makes "unknown" (rather than a
// guess) the answer for any capture that did not originate from an axios call.
// Nothing here throws, and nothing here retains state across a page load.
//
// PRIVACY NOTE - WHAT IS GUARANTEED, AND WHAT IS NOT
// --------------------------------------------------
// `apiRoute` is emitted as an INDEXED, searchable dimension, so a segment that
// rides out verbatim becomes a queryable, cardinality-bearing value. Two
// separate controls apply, and only the first is a guarantee:
//
//  1. GUARANTEED - POSITIONAL. A segment whose PARENT is listed in
//     {@link PARAM_NAME_BY_COLLECTION} is replaced with that collection's
//     parameter name, whatever it looks like, unless it is on the closed,
//     reviewed literal list in {@link COLLECTION_CHILD_LITERALS}. This is
//     fail-CLOSED: an unrecognized child of a known collection is treated as an
//     identifier. It is what makes `/api/colonel/users/alice/diagnostics` and
//     `/api/organizations/onabc/members/bobsmith` safe - none of those ids has
//     the shape the heuristic below looks for, and before the positional rule
//     existed all three rode out verbatim.
//
//  2. BEST EFFORT - SHAPE. Everywhere else, {@link looksLikeIdentifier} is a
//     heuristic, not a proof. A short, all-lowercase, digit-free segment under a
//     parent this module does not know is a collection WILL pass through. The
//     control of last resort is `sanitizeApiRoute` - the ONE function every
//     emitted route goes through, whether it came from the resolver slot or from
//     a caller-supplied `GracefulParseOptions.apiRoute` - which runs the result
//     through `scrubSensitiveStrings` (email / verifiable-identifier /
//     sensitive-path nets) and caps its length.
//
// The practical consequence: EXTENDING `PARAM_NAME_BY_COLLECTION` is how a new
// id-bearing endpoint gets guarantee (1). Leaving it out does not merely lose a
// parameter name - it drops that endpoint's children back to (2).
//
// The heuristic matches on the PERCENT-DECODED segment and treats any segment
// carrying a character outside `[0-9a-zA-Z_-]` as an identifier. Both are
// load-bearing: `encodeURIComponent` is used at every identifier call site, and
// a single dot or `@` used to make a segment fail every shape branch at once -
// which is how `/api/colonel/banned-ips/203.0.113.5` (AdminBannedIps.vue) put an
// end-user IP one hop from the extras field that `actorIdentity` pins
// `ip_address: null` to keep clean.

import { scrubSensitiveStrings } from '@/plugins/core/diagnostics/scrubbers';

/**
 * Resolves the parameterized route for the API call currently in flight.
 * Returns `undefined` when it cannot be determined - which is always the safe
 * answer, and the default.
 */
export type ApiRouteResolver = () => string | null | undefined;

/** Hard cap on an emitted route string. Routes are short; blobs are not. */
const MAX_ROUTE_LENGTH = 120;

/**
 * Collection segments whose CHILD segment is an identifier, mapped to the
 * parameter name the backend routes use. Anything not listed falls back to
 * `:id`, so an unmapped collection still gets parameterized rather than
 * leaking its identifier.
 */
export const PARAM_NAME_BY_COLLECTION: Readonly<Record<string, string>> = {
  organizations: ':org_id',
  organization: ':org_id',
  domains: ':domain_id',
  members: ':member_id',
  memberships: ':membership_id',
  customers: ':cust_id',
  users: ':user_id',
  accounts: ':account_id',
  secret: ':key',
  private: ':key',
  receipt: ':key',
  incoming: ':key',
  invite: ':token',
  confirm: ':token',
};

/**
 * Literal ACTION words that legitimately appear as the CHILD of a segment named
 * in {@link PARAM_NAME_BY_COLLECTION}.
 *
 * This is the ONLY escape from the positional rule, and it is deliberately a
 * CLOSED ALLOWLIST rather than a shape test. The inversion is the whole point:
 * previously a child of a known collection was parameterized only if it LOOKED
 * like an identifier, so every short, lowercase, digit-free id (`alice`,
 * `bobsmith`, `acmecorp`) rode out verbatim into an indexed dimension. Now a
 * child of a known collection is parameterized unless it is written down here.
 *
 * Failure mode of forgetting an entry: a real action route reports as
 * `/api/v3/secret/:key` instead of `/api/v3/secret/conceal` - a loss of
 * aggregation granularity, never a leak. That is the correct direction to fail.
 *
 * HOW THIS SET IS DERIVED, AND HOW IT IS KEPT HONEST
 * -------------------------------------------------
 * It is NOT a judgement call and NOT hand-curated. It is exactly the set of
 * STATIC path segments that sit directly under a {@link PARAM_NAME_BY_COLLECTION}
 * key in the Ruby route table, which is:
 *
 *     apps/api/{account,colonel,domains,incoming,invite,organizations,v1,v2,v3}
 *       /routes.txt        <- the METHOD + PATH lines
 *     apps/api/  ...  /application.rb `@uri_prefix`
 *                          <- the mount prefix each of those paths hangs off
 *
 * A hand-maintained closed list with no regeneration story drifts, and this one
 * did: `status` and `validate` were missing, so three LIVE static endpoints
 * collapsed into a parameter (`/api/v{2,3}/secret/status` -> `/api/v{2,3}/secret/:key`,
 * `/api/incoming/validate` -> `/api/incoming/:key`).
 *
 * So it is machine-checked instead of documented. `collectionChildLiterals.spec.ts`
 * re-derives the set from those two sources on every run and fails with the
 * correct set when the route table and this list disagree. Adding, renaming or
 * deleting a route therefore breaks the spec, not production aggregation:
 *
 *     pnpm vitest run src/tests/utils/telemetry/collectionChildLiterals.spec.ts
 *
 * The current derivation, every entry with a route that exists today:
 *   add          `/api/domains/add`
 *   conceal      `/api/v{2,3}/secret/conceal`, `/api/v{2,3}/guest/secret/conceal`
 *   config       `/api/incoming/config`
 *   dns-widget   `/api/domains/dns-widget/token`
 *   generate     `/api/v{2,3}/secret/generate`, `/api/v{2,3}/guest/secret/generate`
 *   orphaned     `/api/colonel/domains/orphaned`
 *   recent       `/api/v{1,2}/{receipt,private}/recent`, `/api/v3/receipt/recent`
 *   secret       `/api/incoming/secret`
 *   status       `/api/v{2,3}/secret/status`
 *   validate     `/api/incoming/validate`
 *
 * `sso` USED TO BE ON THIS LIST and was removed: it is not the child of any
 * mapped collection anywhere in the route table. Every `sso` route hangs off a
 * resolved id (`/api/domains/:extid/sso`, domains/routes.txt:28-32), whose
 * parent is the extid rather than `domains`, so the positional rule never
 * consulted this set for it. The `sso/mailer` string once cited as its evidence
 * is from colonel/routes.txt:60, a comment listing per-domain config record
 * KINDS (`/api/colonel/domains/:extid/configs/:kind`), not a route.
 */
export const COLLECTION_CHILD_LITERALS: ReadonlySet<string> = new Set([
  'add',
  'conceal',
  'config',
  'dns-widget',
  'generate',
  'orphaned',
  'recent',
  'secret',
  'status',
  'validate',
]);

/**
 * A segment that is ALREADY a route parameter. Callers may hand us a
 * parameterized route (`GracefulParseOptions.apiRoute` does exactly that), and
 * re-parameterizing `:key` into `:id` would corrupt a value that was already
 * correct. Covers the three spellings this codebase and its docs use:
 * `:param`, `{param}` and `$param`.
 *
 * Matched against the DECODED segment, because `new URL().pathname` escapes
 * braces: `{key}` arrives here as `%7Bkey%7D`. It is correctly RECOGNIZED as a
 * parameter, but - since the decoded form is never emitted - it is emitted in
 * that escaped form. Cosmetic, and the safe side of the decode-for-matching
 * -only invariant.
 */
const PARAM_SEGMENT = /^[:{$]/;

/**
 * Anything outside the character class a literal route word is built from.
 *
 * A route word in this API surface is ASCII letters, digits, `_` and `-`
 * (`banned-ips`, `secret-activity`, `v3`). A segment carrying anything else -
 * a DOT (`mail.acmecorp.example`, `203.0.113.5`), an AT SIGN
 * (`alice@example.com`), a COLON (`2001:db8::42`) or a stray PERCENT (an
 * undecodable escape) - is a resolved value, not a route word.
 *
 * This closes the hole that let `/api/colonel/banned-ips/203.0.113.5` and
 * `/api/colonel/users/alice%40example.com` ride out verbatim: every
 * shape-specific branch below requires `^[0-9a-zA-Z_-]+$`, so one dot or one
 * `@` made a segment fail all of them at once.
 */
const NON_ROUTE_WORD = /[^0-9a-zA-Z_-]/;

/** Purely numeric segment (`/12`), always an identifier. */
const NUMERIC_SEGMENT = /^\d+$/;

/** UUID, in either hyphenated or bare form. */
const UUID_SEGMENT = /^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$/i;

/** Prefixed external ids: `org_9f3a…`, `cus_…`, `sub_…`, `acct_…`. */
const PREFIXED_EXTID = /^[a-z]{2,8}_[0-9a-zA-Z]{6,}$/;

/** Long opaque base-36-ish blobs: objids, verifiable identifiers, hashes. */
const OPAQUE_BLOB = /^[0-9a-zA-Z]{16,}$/;

/**
 * True when a path segment looks like a resolved identifier rather than a
 * literal route word.
 *
 * Biased toward false positives ON PURPOSE: over-parameterizing costs one
 * endpoint's worth of aggregation granularity (`/api/colonel/domains/orphaned`
 * reported as `/api/colonel/domains/:domain_id`), while under-parameterizing
 * puts a tenant id in an indexed tag.
 *
 * The bias is cheap here because it currently costs NOTHING: no literal route
 * word anywhere in `apps/api/*` routes.txt is flagged by these branches - not
 * one is 16+ alphanumerics, purely numeric, or 8+ characters carrying a digit.
 * `collectionChildLiterals.spec.ts` asserts that over the whole route table, so
 * a future route word that WOULD be over-parameterized shows up as a test
 * failure rather than as a silently merged endpoint.
 */
function looksLikeIdentifier(segment: string): boolean {
  if (segment.length === 0) return false;
  if (PARAM_SEGMENT.test(segment)) return false;
  if (NON_ROUTE_WORD.test(segment)) return true;
  if (NUMERIC_SEGMENT.test(segment)) return true;
  if (UUID_SEGMENT.test(segment)) return true;
  if (PREFIXED_EXTID.test(segment)) return true;
  if (OPAQUE_BLOB.test(segment)) return true;
  // Mixed alphanumerics containing a digit, longer than a route word.
  return segment.length >= 8 && /\d/.test(segment) && /^[0-9a-zA-Z_-]+$/.test(segment);
}

/**
 * Percent-DECODES a path segment before it is shape-matched.
 *
 * `new URL(...).pathname` preserves percent-encoding, and every call site in
 * this app builds identifier segments with `encodeURIComponent` - so the
 * matcher was being handed `alice%40example.com` and `2001%3Adb8%3A%3A42`,
 * neither of which any pattern here (nor `EMAIL_PATTERN` in the scrubbers,
 * which cannot match `%40`) can see through.
 *
 * Decoding is for MATCHING ONLY; the decoded form is never emitted. A segment
 * whose escapes are malformed keeps its raw form, which still contains `%` and
 * is therefore caught by {@link NON_ROUTE_WORD}.
 */
function decodeSegment(segment: string): string {
  if (!segment.includes('%')) return segment;
  try {
    return decodeURIComponent(segment);
  } catch {
    return segment;
  }
}

/**
 * Converts a request URL (absolute or path-relative, with or without a query
 * string) into a parameterized route.
 *
 * The query string and fragment are DROPPED, not scrubbed: nothing in a query
 * string is part of a route's identity, and dropping is the only treatment with
 * no leak surface at all.
 *
 * @example
 * parameterizeApiPath('/api/colonel/organizations/org_9f3a2b1c8d7e6f50')
 * // '/api/colonel/organizations/:org_id'
 */
export function parameterizeApiPath(url: string): string | undefined {
  if (typeof url !== 'string' || url.length === 0) return undefined;

  let pathname: string;
  try {
    // Synthetic base so bare paths parse; the base is discarded.
    pathname = new URL(url, 'http://_').pathname;
  } catch {
    const cut = url.search(/[?#]/);
    pathname = cut === -1 ? url : url.slice(0, cut);
  }

  const segments = pathname.split('/');
  const out = segments.map((segment, index) => {
    // Match on the DECODED form, emit the literal route word unchanged. A
    // segment that is replaced is replaced outright, so the decoded text never
    // reaches the output either.
    const decoded = decodeSegment(segment);

    // EMPTY SEGMENTS ARE NEVER IDENTIFIERS. `'/api/x/'.split('/')` ends in `''`
    // and `'//'` yields one in the middle, and the positional rule below reads
    // only the PARENT segment - so without this guard a trailing slash
    // manufactured a phantom identifier out of nothing:
    // `/api/organizations/` -> `/api/organizations/:org_id`, which merges a
    // LIST endpoint's failures into its DETAIL endpoint's issue. Not a leak,
    // but it destroys exactly the distinction this module exists to draw.
    // `looksLikeIdentifier` already guards this (`segment.length === 0`); the
    // positional rule runs first and inherited no guard, so it needs its own.
    if (decoded.length === 0) return segment;

    // A caller-supplied route may already be parameterized; re-parameterizing
    // `:key` into `:id` would corrupt a value that was already correct. This
    // check comes first so the positional rule below cannot rewrite it either.
    if (PARAM_SEGMENT.test(decoded)) return segment;

    // POSITIONAL RULE (the guarantee). A child of a known collection is an
    // identifier BY POSITION, whatever its shape, unless it is a reviewed
    // literal. Consulting the collection map only AFTER the shape test - which
    // is what this used to do - meant a known parent could never rescue a short
    // id: `/api/colonel/users/alice` failed every shape branch and shipped
    // `alice` verbatim into an indexed dimension.
    const mapped = PARAM_NAME_BY_COLLECTION[decodeSegment(segments[index - 1] ?? '')];
    if (mapped !== undefined) {
      return COLLECTION_CHILD_LITERALS.has(decoded) ? segment : mapped;
    }

    // SHAPE RULE (best effort). Everywhere else, fall back to the heuristic.
    return looksLikeIdentifier(decoded) ? ':id' : segment;
  });

  const route = out.join('/');
  return route.length > 0 ? route : undefined;
}

/**
 * The default resolver: knows nothing, reports nothing.
 *
 * It stays the default even though the axios slot is wired, because the two are
 * not alternatives: the slot answers for axios-originated captures, and the
 * no-op resolver is what makes "unknown" - rather than a stale or guessed route
 * - the answer for every capture that did not come from one.
 */
const NO_OP_RESOLVER: ApiRouteResolver = () => undefined;

let resolver: ApiRouteResolver = NO_OP_RESOLVER;

/** Route stamped by {@link setCurrentApiRoute}, read by the default slot path. */
let currentRoute: string | undefined;

/**
 * Records the API call currently in flight, as a parameterized route.
 *
 * WIRED AND LIVE. `requestInterceptor` in `src/plugins/axios/interceptors.ts`
 * reaches this function through `noteApiRequestStarted(config.url ?? null)` on
 * every outbound request, before the Pinia store reads that sit inside its
 * try/catch. Every axios call this app makes therefore stamps this slot, and
 * `releaseApiRouteSlot` clears it again once nothing is in flight.
 *
 * Passing `null` clears the slot. The raw URL is parameterized on the way IN,
 * so the resolved form is never retained even in memory.
 */
export function setCurrentApiRoute(url: string | null | undefined): void {
  currentRoute = url ? parameterizeApiPath(url) : undefined;
}

/**
 * Replaces the resolver entirely. For deployments (or tests) that can derive
 * the route more precisely than the axios slot - from a request-scoped async
 * context, say. Pass no argument to restore the no-op default.
 */
export function setApiRouteResolver(next?: ApiRouteResolver): void {
  resolver = next ?? NO_OP_RESOLVER;
}

/** Restores the no-op resolver and clears the slot. Test-cleanup helper. */
export function resetApiRouteContext(): void {
  resolver = NO_OP_RESOLVER;
  currentRoute = undefined;
}

/**
 * Returns the parameterized route to attach to a telemetry event, or
 * `undefined`.
 *
 * Order: an explicitly installed resolver wins; otherwise the axios slot. The
 * result is re-parameterized (a custom resolver may hand back a resolved URL),
 * run through `scrubSensitiveStrings` as a defense-in-depth net, and length
 * -capped. A resolver that throws is treated as "unknown" rather than allowed
 * to break error reporting.
 */
export function resolveApiRoute(): string | undefined {
  let candidate: string | null | undefined;
  try {
    candidate = resolver();
  } catch {
    candidate = undefined;
  }
  if (!candidate) candidate = currentRoute;
  if (!candidate) return undefined;

  return sanitizeApiRoute(candidate);
}

/**
 * THE SINGLE SANITIZER for any route string that is about to be emitted,
 * whoever produced it.
 *
 * Parameterize -> scrub -> cap, in that order, with no way to opt out. It
 * exists because the caller-supplied `GracefulParseOptions.apiRoute` used to
 * take a different, weaker path: it was scrubbed but NOT parameterized, so a
 * caller that passed a resolved URL - which the option's own contract tells
 * them not to do, and which is exactly the mistake a contract cannot prevent -
 * shipped a tenant id into an extras field that nothing downstream scrubs.
 * Routing both producers through one function is what makes the contract true
 * rather than merely documented.
 *
 * Returns `undefined` for anything that cannot be reduced to a route, which is
 * always the safe answer.
 */
export function sanitizeApiRoute(url: string | null | undefined): string | undefined {
  if (!url) return undefined;
  const parameterized = parameterizeApiPath(url);
  if (!parameterized) return undefined;
  return scrubSensitiveStrings(parameterized).slice(0, MAX_ROUTE_LENGTH);
}
