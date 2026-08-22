// src/utils/diagnostics/safeFieldRegistry.ts
//
// LAYER RULE: src/utils/diagnostics/ is pure policy — it must not import from
// `@sentry/*` nor from `src/plugins/`.
//
// ===========================================================================
// SAFE-FIELD REGISTRY - the ONLY sanctioned escape hatch from "types, never
// values" in schema-validation diagnostics.
// ===========================================================================
//
// WHY THIS EXISTS
// ---------------
// `schemaIssueProjection` is deliberately value-free: it ships a field path, an
// issue code and TYPE NAMES, and nothing else. That is enough to diagnose most
// contract drift, but it is NOT enough to diagnose *representation* drift --
// the class of bug where the type name alone is ambiguous.
//
// The motivating case (this branch): `record.subscription_period_end` on the
// Colonel organization-detail response. Familia stores the period end as an
// epoch. Before commit 5f5a8a5732 the four Colonel emit sites returned the raw
// Ruby Integer, so the wire carried `1772940425` where the frontend schema
// expected a string. After 5f5a8a5732 all four sites coerce with `&.to_s`, so
// the wire carries `"1772940425"`. Both are "an epoch"; only one satisfies the
// original schema, and during a mixed-version deployment BOTH are on the wire
// at once.
//
// `received: "number"` vs `received: "string"` distinguishes those two - but
// says nothing about whether the string is a digit-string epoch, an ISO-8601
// date, or garbage, and nothing about whether the magnitude is seconds or
// milliseconds. Those are precisely the questions an operator asks when this
// field breaks. So for THIS field, and only for fields explicitly enrolled
// here, we attach a few extra SHAPE DESCRIPTORS.
//
// WHAT THIS ENTRY IS WORTH TODAY, honestly. The frontend schema has since been
// widened to accept both representations - the field is now
// `z.union([z.string(), z.number()]).nullable().transform(String)` in
// schemas/api/internal/responses/colonel-organizations.ts, verified by parsing
// `subscription_period_end: 1772940425` against it and getting `success: true`.
// So the mixed-version case that motivated the enrollment NO LONGER FAILS, and
// these descriptors do not fire for it. They fire when the field drifts some
// OTHER way (a boolean, an object, an ISO-8601 string from a future producer,
// a millisecond magnitude), which is exactly when the type name alone is again
// ambiguous. The entry is a residual net for the next representation change on
// a field that has already had one - not the live diagnostic for the original
// bug. Do not read the history above as a description of current behaviour.
//
// THE PRIVACY BOUNDARY (read before adding an entry)
// --------------------------------------------------
//  1. ALLOWLIST ONLY. A field gets descriptors because a human decided it is
//     non-sensitive and wrote it down here. There is no inference, no default,
//     no "looks harmless" heuristic.
//  2. EXACT-MATCH KEYS ONLY. The lookup key is `${schema}\u0000${path}`, an
//     exact string compare. No prefix matching, no wildcards, no globs. Prefix
//     matching is the specific failure mode this design refuses: enrolling
//     `record.` would silently extend the exemption to `record.owner_email`,
//     which nobody reviewed.
//  3. DESCRIPTORS, NEVER VALUES. A describer returns a small, fixed vocabulary
//     of enum-like strings derived from the value's SHAPE (typeof,
//     Number.isInteger, /^[0-9]+$/, coarse magnitude bucket). It must never
//     return the value, a substring of it, its length, or a bucket fine enough
//     to reconstruct it. `describeEpochLike` below resolves magnitude to a
//     three-way seconds/millis/micros verdict - that is the granularity
//     ceiling, not a starting point.
//  4. A describer must be TOTAL: any input, including `undefined`, `null`, a
//     function or a cyclic object, yields a descriptor set rather than a throw.
//
// RELATIONSHIP TO THE ACCEPTANCE SUITE
// ------------------------------------
// `src/tests/plugins/core/diagnostics/diagnosticsBoundary.spec.ts` asserts by
// allowlist over the emitted key names, using `SecretResponse` fixtures. No
// `SecretResponse` field is enrolled here, so the default projection is what
// that suite sees - which is the point: registry descriptors are an explicit,
// per-field, reviewed extension of the boundary, never a widening of it.

/**
 * A flat bag of shape descriptors for one enrolled field.
 *
 * Values are always primitive strings so the descriptor can be spread directly
 * into a projected issue row without adding a nesting level (see
 * `schemaIssueProjection` for why nesting depth is load-bearing).
 */
export type SafeFieldDescriptor = Record<string, string>;

/** Derives descriptors for one enrolled field. Must never throw. */
export type SafeFieldDescriber = (value: unknown) => SafeFieldDescriptor;

/**
 * Separator for the composite registry key. NUL cannot occur in a schema name
 * or a Zod path segment, so `schema + SEP + path` is unambiguous and two
 * different pairs can never collide into one key.
 */
const KEY_SEP = '\u0000';

/**
 * Coarse magnitude verdict for an epoch-like integer.
 *
 * The buckets answer exactly one operational question - "is the producer
 * emitting seconds or milliseconds?" - and deliberately nothing finer.
 * `unix_seconds` spans roughly 2001..5138 CE, so learning that a timestamp is
 * "seconds" narrows the underlying value by essentially nothing.
 *
 * @param magnitude - Absolute magnitude of the candidate epoch.
 */
function epochMagnitudeBucket(magnitude: number): string {
  if (!Number.isFinite(magnitude) || magnitude <= 0) return 'unknown';
  if (magnitude < 1e9) return 'below_epoch_range';
  if (magnitude < 1e11) return 'unix_seconds';
  if (magnitude < 1e14) return 'unix_millis';
  if (magnitude < 1e17) return 'unix_micros';
  return 'out_of_range';
}

/** ISO-8601-ish date or date-time, shape only. */
const ISO_8601_SHAPE = /^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2})?)?/;

/** All-digits: the representation `&.to_s` on a Ruby Integer produces. */
const DIGIT_STRING = /^[0-9]+$/;

/** Signed / fractional numeric string. */
const NUMERIC_STRING = /^-?[0-9]+(\.[0-9]+)?$/;

/**
 * Describer for a field that carries a unix epoch on the wire, in any of the
 * representations this codebase has actually shipped.
 *
 * Emits three descriptors:
 *   - `received_type`    - `number` | `string` | `null` | `undefined` | ...
 *   - `numeric_kind`     - how the value encodes a number, if it does:
 *                          `integer` | `float` | `nan` | `digit_string` |
 *                          `numeric_string` | `iso8601_string` |
 *                          `non_numeric_string` | `null` | `non_numeric`
 *   - `timestamp_format` - coarse magnitude verdict from
 *                          {@link epochMagnitudeBucket}, or `iso8601` /
 *                          `unknown` / `not_applicable`.
 *
 * The pair (`received_type`, `numeric_kind`) is what separates the
 * pre-5f5a8a5732 `1772940425` from the post-5f5a8a5732 `"1772940425"`:
 * `number`/`integer` versus `string`/`digit_string`. That distinction is the
 * whole reason this entry exists, so BOTH branches are first-class here rather
 * than one being treated as the anomaly.
 */
export function describeEpochLike(value: unknown): SafeFieldDescriptor {
  if (value === null) {
    return { received_type: 'null', numeric_kind: 'null', timestamp_format: 'not_applicable' };
  }
  if (value === undefined) {
    return {
      received_type: 'undefined',
      numeric_kind: 'non_numeric',
      timestamp_format: 'not_applicable',
    };
  }

  if (typeof value === 'number') {
    if (Number.isNaN(value)) {
      return { received_type: 'number', numeric_kind: 'nan', timestamp_format: 'unknown' };
    }
    return {
      received_type: 'number',
      numeric_kind: Number.isInteger(value) ? 'integer' : 'float',
      timestamp_format: epochMagnitudeBucket(Math.abs(value)),
    };
  }

  if (typeof value === 'string') {
    if (DIGIT_STRING.test(value)) {
      // Parsed only to bucket the magnitude. The parsed number never leaves
      // this function.
      return {
        received_type: 'string',
        numeric_kind: 'digit_string',
        timestamp_format: epochMagnitudeBucket(Number(value)),
      };
    }
    if (ISO_8601_SHAPE.test(value)) {
      return {
        received_type: 'string',
        numeric_kind: 'iso8601_string',
        timestamp_format: 'iso8601',
      };
    }
    if (NUMERIC_STRING.test(value)) {
      return {
        received_type: 'string',
        numeric_kind: 'numeric_string',
        timestamp_format: epochMagnitudeBucket(Math.abs(Number(value))),
      };
    }
    return {
      received_type: 'string',
      numeric_kind: 'non_numeric_string',
      timestamp_format: 'unknown',
    };
  }

  return {
    received_type: Array.isArray(value) ? 'array' : typeof value,
    numeric_kind: 'non_numeric',
    timestamp_format: 'not_applicable',
  };
}

/**
 * THE REGISTRY.
 *
 * Key: `${schemaName}\u0000${dottedFieldPath}` - exact match, both halves.
 * `schemaName` is the `context` argument callers pass to `gracefulParse`
 * (e.g. `'ColonelOrganizationDetailResponse'`), and `dottedFieldPath` is the
 * projected path (e.g. `'record.subscription_period_end'`), array indices
 * included when the field lives under one.
 *
 * Adding an entry is a privacy decision. Review checklist:
 *   - Is this field's *content* non-sensitive for every tenant, always?
 *   - Do the descriptors distinguish REPRESENTATIONS rather than values?
 *   - Could someone with Sentry read access learn anything about a person from
 *     the descriptor vocabulary alone? If yes, do not enroll.
 */
const SAFE_FIELDS: ReadonlyMap<string, SafeFieldDescriber> = new Map<string, SafeFieldDescriber>([
  // #3424 / branch fix/colonel-subscription-period-end.
  // Non-sensitive: a billing period end is an operator-visible schedule date,
  // not user content, and the descriptors resolve it no finer than
  // "seconds-vs-millis".
  [`ColonelOrganizationDetailResponse${KEY_SEP}record.subscription_period_end`, describeEpochLike],
]);

/**
 * Returns the shape descriptors for an enrolled `(schema, path)` pair, or
 * `null` when the pair is not enrolled.
 *
 * `null` is the default for every field in the application. Absence of an
 * entry is never treated as permission.
 *
 * @param schema - The context/schema name passed to `gracefulParse`.
 * @param path - The dotted field path of the failing issue.
 * @param value - The raw value at that path. Inspected, never returned.
 */
export function describeSafeField(
  schema: string | undefined,
  path: string,
  value: unknown
): SafeFieldDescriptor | null {
  if (!schema) return null;
  const describer = SAFE_FIELDS.get(`${schema}${KEY_SEP}${path}`);
  if (!describer) return null;
  try {
    return describer(value);
  } catch {
    // A describer must be total; if one is not, fail closed rather than let an
    // exception escape into the error-reporting path.
    return null;
  }
}

/**
 * True when `(schema, path)` is enrolled, WITHOUT running the describer.
 *
 * This is the truncation priority hook. `schemaIssueProjection` retains an
 * enrolled row unconditionally, ahead of declaration order, because the whole
 * reason a field is enrolled here is that a human decided its failures are the
 * ones worth reading. Before that ordering existed, a Colonel response whose
 * fields all drifted at once pushed `record.subscription_period_end` past the
 * 10-row cap, so the one field this branch exists for was absent from the very
 * events it was meant to explain.
 *
 * It is far past that cap: enumerated from the live schema,
 * `colonelOrganizationDetailRecordSchema` (schemas/api/internal/responses/
 * colonel-organizations.ts) declares 25 fields and `subscription_period_end` is
 * the 21st. Earlier versions of this comment said "the 12th key", and then "24
 * fields" before `organization_ref` was declared; both were wrong. Both
 * ordinals will drift as the schema grows, which is why the claim
 * is pinned by execution rather than by prose: `safeFieldRetention.spec.ts`
 * drifts every field of the REAL schema at once and asserts the enrolled row
 * survives. If enrollment ever stops rescuing it, that spec fails - no ordinal
 * in a comment has to be right for the guarantee to hold.
 *
 * Same exact-match contract as {@link describeSafeField}: no prefixes, no
 * wildcards, and a missing entry is never permission.
 */
export function isSafeFieldEnrolled(schema: string | undefined, path: string): boolean {
  if (!schema) return false;
  return SAFE_FIELDS.has(`${schema}${KEY_SEP}${path}`);
}

/**
 * Diagnostic helper: the enrolled keys in `schema|path` display form.
 * Exported so a spec can assert the registry has not silently grown.
 */
export function enrolledSafeFieldKeys(): string[] {
  return [...SAFE_FIELDS.keys()].map((key) => key.replace(KEY_SEP, '|'));
}
