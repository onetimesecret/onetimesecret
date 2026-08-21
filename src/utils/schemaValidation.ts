// src/utils/schemaValidation.ts
//
// Schema validation with uniform control flow.
// Always returns ParseResult — callers decide the degradation strategy:
//   - List fetches: degrade to empty state
//   - Mutations: throw clean Error for the user
//   - Identity/config: degrade to defaults
//
// Reporting is environment-aware (loud in dev, logged in prod) but control
// flow is identical everywhere, so fallback paths are testable.
//
// Stores are error producers, not handlers. They validate at the API boundary
// and throw clean errors upward. Composables and components handle those errors
// — typically via `wrap` from useAsyncHandler — to classify, log, and present
// them to users. gracefulParse translates raw ZodErrors (schema internals)
// into ParseResult the store can act on, keeping validation details from
// leaking to consuming code.

import { scrubSensitiveStrings } from '@/utils/diagnostics/scrubbers';
import { captureException } from '@/services/diagnostics.service';
import { loggingService } from '@/services/logging.service';
import { resolveApiRoute, sanitizeApiRoute } from '@/utils/diagnostics/apiRouteContext';
import { resolveResourceRefs } from '@/utils/diagnostics/resourceRefRegistry';
import {
  MAX_PROJECTED_ISSUES,
  projectSchemaIssues,
  type ProjectedIssue,
  type SchemaIssueProjection,
} from '@/utils/diagnostics/schemaIssueProjection';
import { z } from 'zod';

/**
 * Discriminated union for parse results.
 * Avoids ambiguity when null could be a valid domain value.
 */
export type ParseResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: z.ZodError | null };

/**
 * Optional, backward-compatible reporting knobs.
 *
 * `gracefulParse(schema, data, context?)` is unchanged; every field here is
 * optional and every default is the safe one.
 */
export interface GracefulParseOptions {
  /**
   * Parameterized API route to attribute the failure to, e.g.
   * `/api/colonel/organizations/:org_id`. Callers that happen to know it may
   * pass it; otherwise it is resolved from the diagnostics route context (see
   * `@/utils/diagnostics/apiRouteContext`). NEVER pass a resolved URL — it is
   * re-parameterized and scrubbed defensively, but the contract is the
   * parameterized form.
   *
   * That sentence used to be false. This option was scrubbed but NOT
   * parameterized, so a caller who passed
   * `/api/colonel/organizations/org_9f3a2b1c8d7e6f50` — the exact mistake the
   * contract asks them not to make, and the one a contract cannot prevent —
   * put a tenant id into an extras field that nothing downstream scrubs. Both
   * producers now go through `sanitizeApiRoute`, so the guarantee is enforced
   * rather than requested.
   */
  apiRoute?: string;
  /** Row cap for the issue projection. Defaults to MAX_PROJECTED_ISSUES. */
  maxIssues?: number;
}

/**
 * Determines if we're in a development or test environment.
 */
function isDevOrTest(): boolean {
  // Vite dev mode
  if (typeof import.meta !== 'undefined' && import.meta.env?.DEV) {
    return true;
  }
  // Node test environment
  if (typeof process !== 'undefined' && process.env?.NODE_ENV === 'test') {
    return true;
  }
  return false;
}

/**
 * Bound on the field-path list embedded in the human-readable message.
 *
 * This was dead for a while: `projection.paths` derived from already-capped
 * rows, so it could never exceed `MAX_PROJECTED_ISSUES`, which is also 10. It
 * is live again — the projection now collects up to `MAX_PROJECTED_PATHS` (40)
 * distinct paths from the FULL issue list so the searchable `schemaField` tag
 * is not bound by the row cap. The message is prose read by a human and stays
 * at 10, with a `…` marker; the tag gets the rest.
 */
const MAX_MESSAGE_PATHS = 10;

/** Bound on the `schemaField` tag value. Sentry tags are indexed; keep them small. */
const MAX_TAG_LENGTH = 200;

// ═══════════════════════════════════════════════════════════════════════════
// THE PRIVACY BOUNDARY, AND THE DIAGNOSTIC-POWER FLOOR
// ═══════════════════════════════════════════════════════════════════════════
//
// A schema-validation failure is the only error class in this app DERIVED FROM
// A RESPONSE PAYLOAD, which makes it the most likely carrier of user data into
// the diagnostics payload. Sentry here is self-hosted, so the concern is data
// minimization inside our own infrastructure — GDPR hygiene, not vendor
// distrust — but the rule is the same either way.
//
// This is a DIAGNOSTICS boundary, not analytics and not metrics. Nothing here
// is emitted on a successful parse, nothing counts usage, and no field is read
// for reporting. Every field below exists so that a specific defect can be
// found and fixed, which is also the argument for keeping the fields it does
// keep: an event too scrubbed to diagnose has no other purpose to fall back on.
//
// WHAT LEAVES THE BROWSER (the approved set, and nothing else):
//     schema/context name . field path . issue code . expected TYPE .
//     received TYPE . issue count . parameterized API route
//
// WHAT NEVER LEAVES:
//   - raw Zod issues, and `issue.message` in particular. Zod v4's built-in
//     messages no longer interpolate the received VALUE (executed: a failed
//     `z.string()` reads "Invalid input: expected string, received number"),
//     but they still interpolate payload-derived KEYS — a failed `.strict()`
//     reads `Unrecognized key: "authorization_token"` — and `ctx.addIssue`,
//     `.refine(fn, msg)` and any custom `error` callback interpolate whatever
//     their author wrote. So the built-in messages are not a safe surface
//     either, and none of them ship: `projectSchemaIssues` feeds every message
//     to `collectRedactionSignals`, which emits only the scrub SENTINELS a
//     message produced. The boundary is safe BY CONSTRUCTION, not by luck.
//   - `unrecognized_keys[].keys` — those are PAYLOAD-DERIVED key names. A real
//     test leaked `authorization_token` this way. Only the count survives, on
//     its own `key_count` key so it can never be misread as an issue total.
//   - `issue.input`, and any value read out of the payload at any path.
//   - `issue.params` wholesale — author-supplied, and one was found carrying
//     `sk_live_SUPER_SECRET`. Only a narrowly-keyed refinement ID is read.
//   - the resolved URL of the failing request, in any field.
//   - a PATH SEGMENT that is not provably schema-authored. For a `z.record()`
//     the Zod path segment IS the payload key, so every segment is scrubbed
//     inside the projection — before it reaches either the tag or the extras.
//
// WHAT NOW LEAVES THAT DID NOT (pass three, deliberately):
//   Schema-authored CONSTANTS — the accepted set of an enum, the format name
//   behind an `invalid_format`, the numeric bound behind a `too_small` /
//   `too_big` — all folded into `expected`. They are written in .ts source, not
//   read off the wire. Dropping them made `z.email()` and `z.url()` failures
//   byte-identical and left enum drift undiagnosable, which is the same bug
//   class as the epoch bug this branch exists for.
//
// WHY EXTRAS ARE THE SHARP EDGE:
//   `createBeforeSendHandler` scrubs exception values, message, request.url,
//   the Referer header, transaction, user and breadcrumbs. It does NOT scrub
//   `event.extra` — nor `event.tags`. Anything placed on EITHER surface is
//   therefore UNSCRUBBED BY CONSTRUCTION and must be safe before it is handed
//   to captureException. That is why the projection is built here rather than
//   filtered later.
//
//   Extras are the sharper of the two only because they are the WIDER surface:
//   a tag is one short string, while `issues` is a whole projected structure.
//   Neither is a filtered surface, so "which surface does this land on" changes
//   the aggregation story, never the scrubbing story. Do not read "it is a tag"
//   as "something downstream will clean it".
//
//   WHICH SURFACE EACH FIELD ACTUALLY LANDS ON is decided by `TAG_FIELDS` in
//   `src/services/diagnostics.service.ts`, NOT here: `applyTagsFromContext`
//   routes every key named there to `scope.setTag` (lowercased) and removes it
//   from the bag before the remainder goes to `scope.setExtras`. Today
//   `schema`, `schemaField`, `apiRoute` and `organization_ref` are on that list
//   and are TAGS; `issueCount` and `issues` are not and are EXTRAS. Check that list before
//   writing "extra X" or "tag X" in a comment — this docblock got `apiRoute`
//   wrong twice, in the one file whose subject is which surface carries what.
//
// THE DIAGNOSTIC-POWER FLOOR (equally non-negotiable):
//   Scrubbing hard enough to make the next bug of this class undiagnosable is a
//   REGRESSION. #3424 burned three fixes because production discarded the
//   failing field. The event must still answer: which field, what kind of
//   failure, what type did the schema want, what type did the wire carry.
//
//   The concrete acceptance case is the bug this branch exists for — the
//   Colonel organization-detail response arriving with
//   `record.subscription_period_end` as an Integer epoch where the schema
//   expected a string. From the emitted event alone an operator must be able to
//   read: path `record.subscription_period_end`, code `invalid_type`, expected
//   `string`, received `number`. Any future tightening that cannot carry that
//   tuple is wrong.
//
//   That tuple is a REQUIREMENT ON THE PROJECTION, not a live reproduction, and
//   this comment used to blur the two. Executed against the schema as it stands:
//   `colonelOrganizationDetailRecordSchema` now declares the field as
//   `z.union([z.string(), z.number()]).nullable().transform(String)`
//   (schemas/api/internal/responses/colonel-organizations.ts), so a numeric
//   epoch PARSES — the field no longer produces that issue at all. The
//   requirement stands for whichever field drifts next; it is asserted in the
//   specs against a schema written for the purpose, because asserting it
//   against the Colonel schema would now assert nothing.
//
// SEE ALSO:
//   src/utils/diagnostics/schemaIssueProjection.ts — the projection and why rows
//     are FLAT (Sentry's normalizeDepth budget; nesting degrades to [Object]).
//   src/utils/diagnostics/safeFieldRegistry.ts — the exact-match allowlist that
//     may add SHAPE descriptors for individually reviewed, non-sensitive fields.
//   src/utils/diagnostics/apiRouteContext.ts — parameterized route resolution.
//   src/tests/plugins/core/diagnostics/diagnosticsBoundary.spec.ts — the
//     end-to-end acceptance suite that enforces both floors.

/**
 * Builds the human-readable message that becomes `exception.values[0].value`.
 *
 * It is assembled FROM THE PROJECTION, never from `issue.message` — the
 * previous implementation interpolated Zod messages here, which is how a
 * refinement message carrying a payload value reached the exception value.
 *
 * `redactionSignals` are the scrub SENTINELS the scrubbers emitted while
 * inspecting those messages — `[EMAIL_REDACTED]`, `[REDACTED]` — never the
 * message text. Their presence tells an operator "some schema is interpolating
 * payload data into its message, go fix that schema" without shipping the
 * interpolation.
 */
function buildErrorMessage(context: string | undefined, projection: SchemaIssueProjection): string {
  const shownPaths = projection.paths.slice(0, MAX_MESSAGE_PATHS);
  const pathList = shownPaths.join(', ') + (projection.paths.length > shownPaths.length ? ', …' : '');

  const codes = [...new Set(projection.rows.map((row) => row.code))].join(', ');

  let message =
    `Schema validation failed${context ? ` for ${context}` : ''}` +
    ` — ${projection.issueCount} issue(s) [${pathList}]: ${codes}`;

  if (projection.truncated) {
    message += ` (projection truncated to ${projection.rows.length - 1} of ${projection.issueCount})`;
  }
  if (projection.redactionSignals.length > 0) {
    message += ` (redacted from issue messages: ${projection.redactionSignals.join(' ')})`;
  }

  return message;
}

/**
 * Parse data with a Zod schema, returning a discriminated result.
 *
 * Always returns ParseResult — never throws. Callers decide what to do
 * with { ok: false } based on context (throw, degrade, ignore).
 *
 * Error reporting is environment-aware:
 * - Dev/test: console.error with the message and the PROJECTED rows. The
 *   projection is used here too — the local console is a screen-share and
 *   bug-report surface, so it gets the same value-free treatment. The raw
 *   ZodError is still returned to the caller, which is where a developer who
 *   genuinely needs the values should read them.
 * - Production: captureException sends the flattened projection to Sentry with
 *   `schema` and `schemaField` promoted to searchable tags.
 *
 * Emitted diagnostic context:
 * - tag   `schema`      — the `context` argument (lowercased by the service)
 * - tag   `schemaField` — comma-joined failing field paths, segment-scrubbed,
 *                         in retention-priority order so the field that matters
 *                         survives the 200-character cut
 * - tag   `apiRoute`    — parameterized route, omitted when unknown. A TAG,
 *                         not an extra: route-level aggregation is the entire
 *                         point of emitting it, and `event.extra` is not
 *                         indexed. Routed there by `TAG_FIELDS` in
 *                         diagnostics.service.ts, which is the authority
 * - tag   `organization_ref` — opaque 16-hex server-derived org pseudonym,
 *                         recovered from the RAW payload for ENROLLED schemas
 *                         only (today: the Colonel organization detail
 *                         response) and shape-checked before it is emitted.
 *                         Absent for every unenrolled schema, and absent when
 *                         the deployment has no keying secret. See
 *                         `@/utils/diagnostics/resourceRefRegistry`
 * - extra `issueCount`  — TRUE total, never the truncated count
 * - extra `issues`      — up to {@link MAX_PROJECTED_ISSUES} flat rows, chosen
 *                         by diagnostic priority rather than declaration order
 *
 * The `service` tag (set once at boot by `createDiagnostics`) is the surface
 * discriminator; there is no separate `surface` tag.
 *
 * @example
 * ```typescript
 * const result = gracefulParse(responseSchemas.secret, response.data, 'SecretResponse');
 * if (!result.ok) {
 *   throw new Error('Unable to load secret. Please try again.');
 * }
 * // result.data is now type-safe and guaranteed valid
 * record.value = result.data.record;
 * ```
 */
export function gracefulParse<T>(
  schema: z.ZodType<T>,
  data: unknown,
  context?: string,
  options?: GracefulParseOptions
): ParseResult<T> {
  const result = schema.safeParse(data);

  if (result.success) {
    return { ok: true, data: result.data };
  }

  // #3424: surface the field(s) that actually failed. Three fixes missed this
  // bug because production discarded the failing field — the generic message
  // reached the local log while the precise `issues[].path` lived only in
  // non-searchable Sentry extras. The failing paths are now both in the message
  // and on a searchable `schemaField` tag, so the next "no longer available"
  // report names its own cause instead of being inferred.
  //
  // Everything sent is derived through `projectSchemaIssues`, which is the
  // single chokepoint for the approved set. Do not add a field to the
  // captureException call below without adding it there first — and read the
  // boundary comment above before you do.
  const projection = projectSchemaIssues(
    result.error,
    data,
    context,
    options?.maxIssues ?? MAX_PROJECTED_ISSUES
  );
  const errorMessage = buildErrorMessage(context, projection);

  if (isDevOrTest()) {
    // Second argument stays an Array so existing consumers/tests that expect a
    // list keep working — it is the projected rows, not the raw issues.
    console.error(errorMessage, projection.rows as ProjectedIssue[]);
  } else {
    // Log locally (the message carries the fields) and send to Sentry with the
    // failing paths promoted to a searchable tag, not just buried in extras.
    const schemaError = new Error(errorMessage);
    loggingService.error(schemaError);

    // Field paths are now segment-scrubbed inside `projectSchemaIssues`, which
    // is the chokepoint BOTH surfaces read from — this tag and the `issues`
    // extras rows. Previously only this half was protected, and extras are
    // unscrubbed by construction (see above), so a `z.record()` path segment
    // that came off the wire reached Sentry through the unprotected half. The
    // pass here is kept as defense in depth over the JOINED value.
    const schemaField = scrubSensitiveStrings(projection.paths.join(',')).slice(0, MAX_TAG_LENGTH);

    // Both route producers — the caller's override and the resolver slot — go
    // through the SAME sanitizer (parameterize, then scrub, then cap). The
    // override used to skip parameterization entirely; see
    // `GracefulParseOptions.apiRoute`.
    const apiRoute = options?.apiRoute ? sanitizeApiRoute(options.apiRoute) : resolveApiRoute();

    // PSEUDONYMOUS RESOURCE CORRELATION — the one place a value is read out of
    // the failing payload and forwarded verbatim.
    //
    // Read from `data` (the RAW argument), not from a parsed record: this
    // branch only runs when `safeParse` FAILED, so there is no parsed record
    // to read. That is not a shortcut, it is the requirement — the whole point
    // is to correlate the failures.
    //
    // Every part of the safety argument lives in `resourceRefRegistry`, which
    // is a fail-closed exact-match allowlist over (schema, path): an unenrolled
    // schema returns `{}`, and an enrolled one still returns `{}` unless the
    // raw value is exactly 16 lowercase hex characters. So the value forwarded
    // here is either an opaque server-derived pseudonym or nothing at all — a
    // wrong-shaped, uppercase, numeric, object, null or absent value yields no
    // key, and no key means `applyTagsFromContext` never sees one.
    //
    // These become TAGS, not extras: every name the registry can emit is
    // listed in `TAG_FIELDS` in diagnostics.service.ts (asserted by
    // `resourceRefRegistry.spec.ts`, which reads the registry's own tag names
    // rather than a copy of them). Tag because aggregating by ref is the
    // entire point — `organization_ref` distinguishes "one org is broken" from
    // "every org is broken" on a route deliberately parameterized to
    // `:org_id`, and `event.extra` is not indexed, so a ref living there could
    // never be counted.
    const resourceRefs = resolveResourceRefs(context, data);

    captureException(schemaError, {
      schema: context,
      schemaField,
      // Omitted entirely when unknown, rather than passed as `undefined`.
      // `applyTagsFromContext` would skip an undefined value anyway, but it
      // would NOT skip an empty string — `setTag('apiRoute', '')` is a real,
      // useless indexed value — so the guard is on truthiness here.
      //
      // This key becomes a TAG, not an extra: `apiRoute` is listed in
      // `TAG_FIELDS` in diagnostics.service.ts, so `applyTagsFromContext` sends
      // it to `scope.setTag` (lowercased) and drops it from the extras bag.
      // That is deliberate — `apiRoute:"/api/colonel/organizations/:org_id"` is
      // a query an operator runs, and extras are not indexed. It is safe on an
      // indexed dimension because `sanitizeApiRoute` parameterized, scrubbed
      // and capped it first, so cardinality is bounded by the route table.
      //
      // The axios interceptor IS wired (`requestInterceptor` stamps the slot on
      // every request), so this is populated for any parse of an axios-delivered
      // payload; "unknown" now means the capture did not originate from an axios
      // call at all.
      ...(apiRoute ? { apiRoute } : {}),
      // Empty for every schema that is not enrolled, which is every schema in
      // the app except the Colonel organization detail response.
      ...resourceRefs,
      issueCount: projection.issueCount,
      issues: projection.rows,
    });
  }

  return { ok: false, error: result.error };
}

/**
 * Strict parse that always throws on validation failure.
 * Use for critical paths where invalid data should halt execution.
 */
export function strictParse<T>(schema: z.ZodType<T>, data: unknown): T {
  return schema.parse(data);
}
