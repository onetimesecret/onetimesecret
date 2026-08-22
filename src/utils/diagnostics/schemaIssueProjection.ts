// src/utils/diagnostics/schemaIssueProjection.ts
//
// REFERENCE: docs/architecture/diagnostics-privacy-boundary.md
//
// LAYER RULE: src/utils/diagnostics/ is pure policy — it must not import from
// `@sentry/*` nor from `src/plugins/`. This module decides WHAT a failure is
// allowed to say; the plugin layer decides how it is sent.
//
// ===========================================================================
// SCHEMA-ISSUE PROJECTION - the value-free rendering of a ZodError.
// ===========================================================================
//
// This is a DIAGNOSTICS projection, not analytics and not metrics: it runs only
// when a parse FAILS, and every field it emits exists to make that failure
// diagnosable. Nothing here measures usage or counts events for reporting.
//
// THE TWO PROPERTIES THAT MUST HOLD AT ONCE
// -----------------------------------------
// PRIVACY FLOOR
//   A schema-validation failure is the one error class in this app that is
//   *derived from a response payload*. It is therefore the most likely carrier
//   of user data into Sentry. The Sentry here is self-hosted, so this is
//   data-minimization inside our own infrastructure rather than vendor
//   distrust - but the rule is the same: the outbound event carries METADATA
//   ABOUT the failure, never the payload that caused it.
//
//   Concretely, and non-negotiably, none of these leave the browser:
//     - `issue.message` (Zod's own text, built-in or custom)
//     - `issue.keys` from `unrecognized_keys` (payload-DERIVED key names; a
//       real test leaked `authorization_token` this way)
//     - `issue.input`, or any value read out of the payload
//     - `issue.pattern` from `invalid_format` (a regex is authored, but it is
//       verbose, low-value in a tag, and can encode more than its author meant)
//     - `issue.params` WHOLESALE. `params` is author-supplied through
//       `ctx.addIssue`, and an audit found a real one carrying
//       `sk_live_SUPER_SECRET`. Only a narrowly-keyed, scrubbed, length-capped
//       refinement ID is read out of it.
//
//   SCHEMA-AUTHORED CONSTANTS ARE NOT PAYLOAD (revised, pass three)
//     `issue.values` (`invalid_value`), `issue.format` (`invalid_format`) and
//     `issue.minimum` / `maximum` / `origin` / `inclusive` (`too_small` /
//     `too_big`) all originate in .ts schema SOURCE, never on the wire. Dropping
//     them cost real diagnostic power for zero privacy gain: a `z.email()` and a
//     `z.url()` failure were byte-identical on the wire, and enum drift - the
//     same bug class as the epoch bug this branch exists for - reported only
//     "invalid_value" with no way to ask what the schema accepts. They are now
//     emitted, folded into the single `expected` field, and every one of them is
//     scrubbed and bounded on the way out so that a schema which ever starts
//     building an enum at runtime fails CLOSED rather than leaking.
//
// DIAGNOSTIC-POWER FLOOR
//   Over-scrubbing is a regression, not a win. #3424 burned three fixes
//   precisely because production discarded the failing field. The projection
//   MUST still let an operator answer, from the event alone:
//     "which field, what kind of failure, what type did the schema want, what
//      type did the wire actually carry?"
//   That is exactly what diagnosed the bug this branch exists for:
//   `record.subscription_period_end`, `invalid_type`, expected `string`,
//   received `number`. If a future tightening cannot carry that tuple, the
//   tightening is wrong.
//
// SO THE APPROVED SET IS EXACTLY:
//   schema/context name . field path . issue code . expected type .
//   received type . issue count . parameterized API route
//
// WHY THE ROWS ARE FLAT
// ---------------------
// Sentry normalizes `event.extra` with `normalizeDepth` (default 3) before
// transport. `normalize()` returns primitives verbatim at ANY depth but
// replaces a still-nested object with the string `[Object]` (and an array with
// `[Array]`) once the budget runs out. With
//
//     extra = { issues: [ { path, code, expected, received } ] }
//
// the containers sit at depths 1 and 2 and every leaf is a primitive, so the
// whole projection survives the default budget. Add ONE more nesting level -
// e.g. `{ issues: { "0": { detail: { ... } } } }` - and the innermost rows
// degrade to `[Object]`, which is the exact failure the acceptance suite
// forbids. Keep rows flat: string keys, primitive values, no exceptions.
//
// The nested field PATH is carried as a pre-joined dotted string
// (`record.items.0.nested.field`) rather than a `string[]`, for the same
// reason: a joined string is a primitive and can never be normalized into
// `[Array]`, and it is what an operator actually greps for in Sentry search.

import { scrubSensitiveStrings } from '@/utils/diagnostics/scrubbers';
import type { z } from 'zod';

import { describeSafeField, isSafeFieldEnrolled } from './safeFieldRegistry';

/**
 * Upper bound on projected rows. A ZodError over a list response can carry one
 * issue per row per field - hundreds of them - and every one of those rows is
 * transport cost and normalization surface for no added diagnostic value: the
 * first handful already names the failing shape.
 *
 * The TRUE total is always reported separately as `issueCount`, so the bound
 * never hides the magnitude of a failure.
 */
export const MAX_PROJECTED_ISSUES = 10;

/**
 * Guard on how deep union recursion may go. `invalid_union` nests a full issue
 * list per union member, and members can themselves be unions. Bounded so a
 * pathological schema cannot turn error reporting into a stack overflow.
 */
const MAX_UNION_DEPTH = 3;

/**
 * Upper bound on DISTINCT field paths collected for the `schemaField` tag.
 *
 * Deliberately larger than {@link MAX_PROJECTED_ISSUES}: paths are short, they
 * are already segment-scrubbed, and that tag is the ONE indexed dimension an
 * operator can search on (`schemaField:record.subscription_period_end`). Rows
 * are transport and normalization cost; paths are the index. Binding them to
 * the same cap meant a wide failure - a Colonel response drifting all at once
 * during a mixed-version rollout - silently removed the failing field from the
 * only searchable surface it had.
 *
 * The consumer additionally caps the joined tag VALUE at 200 characters
 * (Sentry's own tag limit), so this bound is about how many candidates the cut
 * gets to choose from, not about the wire size.
 */
export const MAX_PROJECTED_PATHS = 40;

/** Path shown for an issue that failed at the root of the parsed value. */
export const ROOT_PATH = '(root)';

/** Replacement for a path segment that is not provably schema-authored. */
export const REDACTED_SEGMENT = '[REDACTED]';

/** Bound on the composed `expected` string. Sentry indexes it; keep it small. */
const MAX_EXPECTED_LENGTH = 120;

/** How many accepted literals an `invalid_value` row may name. */
const MAX_ACCEPTED_VALUES = 8;

/** Per-literal cap inside that set. */
const MAX_ACCEPTED_VALUE_LENGTH = 32;

/** Bound on the derived `issueCode` discriminator for a `custom` issue. */
const MAX_ISSUE_CODE_LENGTH = 64;

/**
 * One projected issue: FLAT, string keys, primitive values only.
 *
 * Every key here is inside the approved set. `issueCount` appears at row level
 * only for issue kinds whose payload is a COUNT rather than a value - today
 * `unrecognized_keys` (how many extra keys the payload carried) and the
 * synthetic truncation row.
 *
 * Registry descriptors (see `safeFieldRegistry`) are spread into the row for
 * explicitly enrolled fields, which is why the index signature exists.
 */
export interface ProjectedIssue {
  /** Dotted field path, array indices included. `(root)` when empty. */
  path: string;
  /** Zod issue code, e.g. `invalid_type`, `unrecognized_keys`, `custom`. */
  code: string;
  /**
   * What the SCHEMA declared, in whatever form the issue kind expresses it.
   * One field carries all of it, because every source is schema-authored and
   * an operator asks one question ("what did the schema want?"), not four:
   *
   *   `invalid_type`   -> the declared type name        `string`
   *   `invalid_value`  -> the accepted literal set      `"ok"|"stale"|"error"`
   *   `invalid_format` -> the validator that fired      `email`
   *   `too_small`      -> origin and bound              `string >=8`
   *   `too_big`        -> origin and bound              `number <=5`
   *
   * Folding them together is also what keeps the emitted key vocabulary stable
   * against the acceptance suite's allowlist - see {@link composeExpected}.
   */
  expected?: string;
  /** Type NAME (never the value) actually found at `path` in the payload. */
  received?: string;
  /**
   * Sub-code for a `custom` issue: the author-declared refinement id when the
   * refinement supplies one, else a `shape:` discriminator. See
   * {@link describeCustomIssue}.
   */
  issueCode?: string;
  /** TRUE issue total. Row level only, and only on the truncation sentinel. */
  issueCount?: number;
  /** How many unrecognized keys the payload carried. NEVER their names. */
  key_count?: number;
  /** Descriptors from the safe-field registry, for enrolled fields only. */
  [descriptor: string]: string | number | undefined;
}

/** The full, bounded projection of one ZodError. */
export interface SchemaIssueProjection {
  /** Bounded, flat rows. Length <= MAX_PROJECTED_ISSUES (+1 truncation row). */
  rows: ProjectedIssue[];
  /** TRUE total issue count, after union flattening. Never truncated. */
  issueCount: number;
  /** Whether `rows` omits issues that `issueCount` counts. */
  truncated: boolean;
  /**
   * Unique dotted field paths, segment-scrubbed, in RETENTION-PRIORITY order
   * (see {@link projectSchemaIssues}), bounded by {@link MAX_PROJECTED_PATHS}.
   *
   * Derived from the FULL issue list, not from the surviving rows: this list
   * feeds the one indexed, searchable tag, so it must not inherit the row cap.
   */
  paths: string[];
  /**
   * Redaction SENTINELS (e.g. `[EMAIL_REDACTED]`) that the scrubbers emitted
   * while inspecting the issue messages - never the messages themselves. See
   * {@link collectRedactionSignals}.
   */
  redactionSignals: string[];
}

/**
 * Names the TYPE of a value without revealing the value.
 *
 * Deliberately a little finer than `typeof` where the extra granularity is
 * diagnostic and value-free: `null`, `array`, `date` and `nan` are all things
 * an operator needs distinguished from the flat `object`/`number` that
 * `typeof` would report, and none of them narrows the underlying data.
 */
export function typeNameOf(value: unknown): string {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (value instanceof Date) return 'date';
  const t = typeof value;
  if (t === 'number' && Number.isNaN(value)) return 'nan';
  return t;
}

/**
 * Reads the value at a Zod issue path out of the parsed input.
 *
 * The value is used for TWO purposes only, both of which discard it
 * immediately: naming its type ({@link typeNameOf}) and, for explicitly
 * enrolled fields, deriving shape descriptors (`safeFieldRegistry`). It is
 * never stored, stringified or emitted.
 *
 * Returns `undefined` when the path does not resolve, which is itself
 * meaningful (`received: "undefined"` is how a missing required field reads).
 */
function valueAtPath(input: unknown, path: ReadonlyArray<PropertyKey>): unknown {
  let cursor: unknown = input;
  for (const segment of path) {
    if (cursor === null || cursor === undefined) return undefined;
    if (typeof cursor !== 'object' && typeof cursor !== 'function') return undefined;
    cursor = (cursor as Record<PropertyKey, unknown>)[segment];
  }
  return cursor;
}

// ---------------------------------------------------------------------------
// PATH SEGMENTS ARE NOT ALWAYS SCHEMA-AUTHORED
// ---------------------------------------------------------------------------
//
// A Zod path segment is USUALLY a field name written in a .ts schema, and those
// are the diagnostic payload this module exists to preserve. But for a
// `z.record(...)` the segment IS THE PAYLOAD KEY, and for an `invalid_key`
// issue it is the payload key that failed the key schema. Both are reachable
// today through `gracefulParse`: colonel-sessions.ts:113 (`data: z.record`,
// keys explicitly arbitrary), colonel.ts, colonel-billing.ts, the Stripe
// `metadata` records in account/stripe-types.ts, and errors/types.ts.
// Reproduced against this projector before the fix:
//
//   z.record(z.string(), z.number()) + {"alice@example.com": "nope"}
//     -> path === "alice@example.com"
//   z.record(z.uuid(), z.number())   + {"sk_live_51H8xQzABCDEF": 1}
//     -> code invalid_key, path === "sk_live_51H8xQzABCDEF"
//
// The consumer scrubbed the `schemaField` TAG and even documented this hazard
// while shipping `rows` to `event.extra`, which nothing downstream scrubs. So
// the control belongs HERE, at the one chokepoint both surfaces read from.
//
// SCRUB PER SEGMENT, NEVER PER PATH. Flattening `record.<key>.value` to one
// token would destroy the #3424 contract - the readable schema-authored parent
// is most of the diagnostic value. `record.[REDACTED].value` keeps it.

/** An array index. Checked FIRST: `0` is a legitimate, non-identifying path. */
const ARRAY_INDEX = /^\d{1,9}$/;

/** The shape of a field name a .ts schema can declare. */
const SCHEMA_FIELD_NAME = /^[A-Za-z_$][A-Za-z0-9_$]{0,63}$/;

/**
 * Defense in depth behind {@link scrubSensitiveStrings}, for the narrow
 * PATH-SEGMENT domain only.
 *
 * The scrubbers own the prefix and network nets (`org_`, `cus_`, `sub_`, `sk_`,
 * IPv4/IPv6) and are the primary control; this is not a second copy of them.
 * It is a different question, answerable only here: a path segment is drawn
 * from a far narrower alphabet than free text, so "does any `_`-delimited word
 * in this segment look machine-generated?" is decidable without a prefix list.
 *
 * A word qualifies as opaque at >= 8 alphanumerics carrying >= 3 digits. Both
 * thresholds were fitted against the REAL digit-bearing field names in
 * src/schemas, every one of which survives: `display_name_i18n_key`,
 * `max_24_hour_send`, `sent_last_24_hours`, `utf8_sanitizer`, `d9s_enabled`,
 * `smtp2go`, `last4`, `v1BurnSecret`. Over-scrubbing a real field name is the
 * regression this guard must not cause.
 */
function hasOpaqueToken(segment: string): boolean {
  for (const word of segment.split(/[_$]/)) {
    if (word.length < 8) continue;
    if (!/^[0-9a-zA-Z]+$/.test(word)) continue;
    let digits = 0;
    for (const ch of word) if (ch >= '0' && ch <= '9') digits += 1;
    if (digits >= 3) return true;
  }
  return false;
}

/** Segment-scrub results are memoized: the same field names recur per event. */
const segmentCache = new Map<string, string>();

/**
 * Renders ONE path segment in a form safe for an unscrubbed extras field.
 *
 * Fails CLOSED: anything not provably schema-authored becomes
 * {@link REDACTED_SEGMENT}. When the scrubbers fire we emit the plain sentinel
 * rather than their partially-rewritten output, because a partial rewrite can
 * leave the unmatched remainder of a payload key behind.
 */
function projectPathSegment(segment: string): string {
  const cached = segmentCache.get(segment);
  if (cached !== undefined) return cached;

  let result: string;
  if (ARRAY_INDEX.test(segment)) {
    result = segment;
  } else if (scrubSensitiveStrings(segment) !== segment) {
    result = REDACTED_SEGMENT;
  } else if (!SCHEMA_FIELD_NAME.test(segment)) {
    result = REDACTED_SEGMENT;
  } else if (hasOpaqueToken(segment)) {
    result = REDACTED_SEGMENT;
  } else {
    result = segment;
  }

  if (segmentCache.size > 512) segmentCache.clear();
  segmentCache.set(segment, result);
  return result;
}

/**
 * Joins a Zod path into the dotted form used everywhere downstream, scrubbing
 * each segment on the way. See the block comment above for why.
 */
function joinPath(path: ReadonlyArray<PropertyKey>): string {
  if (path.length === 0) return ROOT_PATH;
  return path.map((segment) => projectPathSegment(String(segment))).join('.');
}

/**
 * Zod issue shape, read structurally rather than through Zod's discriminated
 * union so this module keeps working across Zod point releases that add or
 * rename issue kinds.
 *
 * `input` is intentionally absent: it is the raw failing value, nothing here
 * may read it, and leaving it undeclared means a future edit has to add it
 * deliberately rather than reach it by accident. `message` is absent for the
 * same reason but is NOT unreachable - two call sites read it through an
 * explicit cast (`collectRedactionSignals`, which keeps only the scrub
 * sentinels, and `describeCustomIssue`, which keeps only a token-class shape).
 * Both discard the text; the cast is the reminder that reading it is a
 * deliberate act.
 *
 * `keys` and `values` ARE declared, and are read under the restrictions noted
 * on each: `keys` for its LENGTH only, `values` only through `safeConstant`.
 */
interface RawIssueLike {
  code?: string;
  path?: ReadonlyArray<PropertyKey>;
  expected?: unknown;
  /** `invalid_union` member errors - Zod v4 spelling. */
  errors?: unknown;
  /** `invalid_union` member errors - Zod v3 spelling. */
  unionErrors?: unknown;
  /** `unrecognized_keys` - read for its LENGTH only, never its contents. */
  keys?: unknown;
  /** `invalid_value` - the ACCEPTED literal set, authored in schema source. */
  values?: unknown;
  /** `invalid_format` - which string validator fired: `email`, `url`, `uuid`. */
  format?: unknown;
  /** `too_small` / `too_big` / `invalid_format` - what was measured. */
  origin?: unknown;
  /** `too_small` bound, authored in schema source. */
  minimum?: unknown;
  /** `too_big` bound, authored in schema source. */
  maximum?: unknown;
  /** Whether the bound is `>=`/`<=` rather than `>`/`<`. */
  inclusive?: unknown;
  /** `custom` - author-supplied bag. Read for a refinement ID key ONLY. */
  params?: unknown;
}

/**
 * Trims and hard-caps a schema-authored constant, then refuses it outright if a
 * scrub pass changed it.
 *
 * The no-runtime-enum claim was re-verified for this tree (every `z.enum` and
 * `z.literal` under src/schemas is built from a module-level `as const` tuple
 * or a string literal), but a claim about today's source is not a control. This
 * is: if a constant ever starts carrying payload, the scrubbers see it and the
 * whole field is dropped rather than partially rewritten.
 */
function safeConstant(text: string, limit: number): string | undefined {
  const trimmed = text.trim().slice(0, limit);
  if (trimmed.length === 0) return undefined;
  if (scrubSensitiveStrings(trimmed) !== trimmed) return undefined;
  return trimmed;
}

/** Renders one accepted literal. Non-primitives are refused, not stringified. */
function renderAcceptedValue(value: unknown): string | undefined {
  if (value === null) return 'null';
  const kind = typeof value;
  if (kind === 'string') return safeConstant(`"${value as string}"`, MAX_ACCEPTED_VALUE_LENGTH);
  if (kind === 'number' || kind === 'boolean' || kind === 'bigint') {
    return safeConstant(String(value), MAX_ACCEPTED_VALUE_LENGTH);
  }
  return undefined;
}

/** A bound is emittable only if it is a plain finite number or a bigint. */
function renderBound(value: unknown): string | undefined {
  if (typeof value === 'bigint') return String(value);
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return undefined;
}

/** `string` / `number` / `array` / `record` - Zod's own origin vocabulary. */
const ORIGIN_NAME = /^[a-z_]{1,24}$/;

/** `email` / `url` / `uuid` / `datetime` / `regex` - Zod's format vocabulary. */
const FORMAT_NAME = /^[a-z0-9_]{1,32}$/i;

/**
 * Composes the single `expected` field from whichever schema-authored
 * constants this issue kind carries.
 *
 * WHY ONE FIELD AND NOT FIVE. The end-to-end acceptance suite
 * (diagnosticsBoundary.spec.ts) asserts by ALLOWLIST over emitted key names, and
 * `expected` is the approved spelling for "what the schema declared". Adding
 * `format`, `minimum`, `maximum`, `origin` and `inclusive` as five new row keys
 * would widen that vocabulary five times over for one concept. Composition
 * keeps the vocabulary fixed while the diagnostic content grows, and the
 * composed value stays a primitive string so nothing can normalize to
 * `[Object]`.
 *
 * Everything read here is authored in .ts schema source. `invalid_format`'s
 * `pattern` is the one exception that stays dropped: a regex is verbose, adds
 * little a format name does not, and can encode more than its author intended.
 */
function composeExpected(issue: RawIssueLike): string | undefined {
  if (typeof issue.expected === 'string') {
    return safeConstant(issue.expected, MAX_EXPECTED_LENGTH);
  }
  if (issue.code === 'invalid_value') return expectedFromValues(issue);
  if (issue.code === 'invalid_format') return expectedFromFormat(issue);
  if (issue.code === 'too_small' || issue.code === 'too_big') return expectedFromBound(issue);
  return undefined;
}

/** `invalid_value` -> the accepted literal set, e.g. `"ok"|"stale"|"error"`. */
function expectedFromValues(issue: RawIssueLike): string | undefined {
  if (!Array.isArray(issue.values)) return undefined;

  const rendered: string[] = [];
  for (const value of issue.values.slice(0, MAX_ACCEPTED_VALUES)) {
    const text = renderAcceptedValue(value);
    // One unrenderable member drops the whole set: a partial accepted-set is
    // worse than none, because it reads as complete.
    if (text === undefined) return undefined;
    rendered.push(text);
  }
  if (rendered.length === 0) return undefined;

  const suffix = issue.values.length > MAX_ACCEPTED_VALUES ? '|…' : '';
  return safeConstant(rendered.join('|') + suffix, MAX_EXPECTED_LENGTH);
}

/** `invalid_format` -> which string validator fired. `pattern` stays dropped. */
function expectedFromFormat(issue: RawIssueLike): string | undefined {
  if (typeof issue.format !== 'string') return undefined;
  if (!FORMAT_NAME.test(issue.format)) return undefined;
  return safeConstant(issue.format, MAX_EXPECTED_LENGTH);
}

/** `too_small` / `too_big` -> what was measured and the bound it violated. */
function expectedFromBound(issue: RawIssueLike): string | undefined {
  const isSmall = issue.code === 'too_small';
  const bound = renderBound(isSmall ? issue.minimum : issue.maximum);
  if (bound === undefined) return undefined;

  const comparator = (isSmall ? '>' : '<') + (issue.inclusive === false ? '' : '=');
  const named = typeof issue.origin === 'string' && ORIGIN_NAME.test(issue.origin);
  const origin = named ? `${issue.origin as string} ` : '';
  return safeConstant(`${origin}${comparator}${bound}`, MAX_EXPECTED_LENGTH);
}

/**
 * Keys under `issue.params` that may carry a refinement ID.
 *
 * `params` is author-supplied through `ctx.addIssue`, so it is emphatically NOT
 * emitted wholesale - an audit of this codebase found a real params bag
 * carrying `sk_live_SUPER_SECRET`. Only these names are read, and only when the
 * value survives {@link REFINEMENT_ID} and {@link safeConstant}.
 *
 * Each name here has to read as "WHICH RULE FIRED", never as "the value that
 * failed". `code` was on this list and is not any more: it is the one spelling
 * that an author naturally reaches for to carry the offending value
 * (`params: { code: order.customerCode }`), and a scrub-clean value such as
 * `alice` or `acme-corp-tenant` then rode out verbatim as `issueCode`. Dropping
 * it costs nothing - a refinement that wants an id has four other spellings,
 * and one that supplies none still gets the `shape:` discriminator below.
 *
 * THE RESIDUAL RISK ON THESE FOUR NAMES IS AUTHOR DISCIPLINE. Not REFINEMENT_ID,
 * and an earlier version of this comment claiming otherwise was wrong. Executed
 * against this projector:
 *
 *     params: { id: 'alice' }                -> issueCode "alice"
 *     params: { refinement: 'acme-corp-tenant' } -> issueCode "acme-corp-tenant"
 *
 * - the same two values named above as the leak that motivated dropping `code`.
 * Removing `code` moved the hole from one key spelling to four; it did not
 * close it.
 *
 * WHY IT IS NOT CLOSED HERE. `must-exceed-min` and `acme-corp-tenant` are the
 * same lexical class - a lowercase kebab word - so no shape predicate can tell
 * a rule id from a tenant slug. The only construction that WOULD make the claim
 * true is a registry of known refinement ids, with anything unregistered
 * falling back to `shape:`. That is deliberately not built: NOTHING in src/
 * supplies `params` to `ctx.addIssue` today (the two producers,
 * schemas/contracts/custom-domain/{sso,signup}-config.ts, pass only
 * `code`/`message`/`path`), so a registry would be unexercised machinery whose
 * fail-closed branch is already what an author gets by supplying no id at all.
 *
 * WHAT IS ACTUALLY BOUNDED, then, and it is worth having:
 *   - PUNCTUATION, by {@link REFINEMENT_ID} - executed: `bob.smith` and
 *     `2001:db8::42` are refused and fall through to `shape:`.
 *   - ANYTHING THE SCRUBBERS RECOGNIZE, by {@link safeConstant} - executed:
 *     `alice@example.com` and `sk_live_51H8xQzABCDEF` are refused the same way.
 *     That is what covers prefixed external ids (`org_`, `cus_`, `sub_`, `sk_`).
 *   - LENGTH, at {@link MAX_ISSUE_CODE_LENGTH}.
 *
 * What survives all three is a short, scrub-clean, punctuation-free word. If
 * that word is a bare tenant slug or username, it reaches an emitted field
 * verbatim, and the only thing that prevents it is the author of the refinement
 * writing a RULE NAME here. Say so in review of any new `ctx.addIssue` params.
 */
const REFINEMENT_ID_KEYS = ['id', 'rule', 'refinement', 'name'] as const;

/**
 * Vocabulary a refinement ID may use. Anything else is refused outright.
 *
 * Deliberately narrower than "a short safe string": a refinement id is a
 * SOURCE-CODE IDENTIFIER, so it starts with a letter and is built from letters,
 * digits, `_` and `-`. DOTS and COLONS used to be accepted, which is what let
 * `bob.smith`, `mail.acmecorp.example` and `2001:db8::42` through the four
 * remaining key names - all of them value-shaped, none of them rule-shaped.
 * Excluding those two characters does not narrow any id an author would
 * plausibly write (`period_end_shape`, `must-exceed-min`), and it removes the
 * two punctuation marks that distinguish a hostname, an email local-part-ish
 * token or an address from an identifier.
 *
 * A `shape:` discriminator is produced elsewhere and never validated here, so
 * dropping `:` from this class does not affect it.
 *
 * This bounds PUNCTUATION and nothing else. A value-shaped word carrying no
 * punctuation (`alice`, `acme-corp-tenant`) passes - see the residual-risk note
 * on {@link REFINEMENT_ID_KEYS} for why that is documented rather than fixed.
 */
const REFINEMENT_ID = /^[A-Za-z][A-Za-z0-9_-]{0,63}$/;

/**
 * Gives a `custom` issue an identity without shipping its message.
 *
 * THE PROBLEM. Two different `.refine()` rules on one object, or a
 * `superRefine` adding several issues at one path, collapse to N identical
 * `{ path: "(root)", code: "custom" }` rows. `redactionSignals` yields nothing
 * for a message that does not interpolate (verified: "a must exceed 3 chars"
 * scrubs to itself), so a static literal message produced ZERO signal - pure
 * diagnostic loss with no privacy gain, since the baseline shipped the message.
 *
 * Failing closed on message TEXT is right; emitting nothing in its place is
 * not. So, in order:
 *
 *  1. AN AUTHOR-DECLARED ID from `params`, under one of
 *     {@link REFINEMENT_ID_KEYS} and matching {@link REFINEMENT_ID}. This is
 *     the correct answer and the one to reach for when writing a refinement:
 *     `ctx.addIssue({ code: 'custom', params: { id: 'period_end_shape' } })`.
 *     Note that `params.code` is NOT read: it is the name authors reach for to
 *     carry the offending VALUE, so it is refused by key rather than by luck.
 *
 *  2. A SHAPE DISCRIMINATOR derived from the message's TOKEN CLASSES, never its
 *     text. Each whitespace-delimited token becomes one character - `a` all
 *     letters, `9` all digits, `x` alphanumeric mixed, `p` punctuation only,
 *     `s` anything else - over a five-symbol alphabet, capped at 12 tokens.
 *     "must exceed 3 chars" -> `shape:aa9a`; "must have a name" -> `shape:aaaa`.
 *     Distinguishable, stable across events, and non-reversible by
 *     construction: the mapping is many-to-one and destroys every character.
 *     The message is scrubbed BEFORE classing, so an interpolated email
 *     contributes the class of `[EMAIL_REDACTED]` rather than of the address.
 */
function describeCustomIssue(issue: RawIssueLike, message: string | undefined): string | undefined {
  const params = issue.params;
  if (params && typeof params === 'object' && !Array.isArray(params)) {
    for (const key of REFINEMENT_ID_KEYS) {
      const candidate = (params as Record<string, unknown>)[key];
      if (typeof candidate !== 'string') continue;
      if (!REFINEMENT_ID.test(candidate)) continue;
      const safe = safeConstant(candidate, MAX_ISSUE_CODE_LENGTH);
      if (safe) return safe;
    }
  }

  if (typeof message !== 'string' || message.trim().length === 0) return undefined;

  const tokens = scrubSensitiveStrings(message).trim().split(/\s+/).slice(0, 12);
  const shape = tokens
    .map((token) => {
      if (/^[A-Za-z]+$/.test(token)) return 'a';
      if (/^[0-9]+$/.test(token)) return '9';
      if (/^[0-9A-Za-z]+$/.test(token)) return 'x';
      if (/^[^0-9A-Za-z]+$/.test(token)) return 'p';
      return 's';
    })
    .join('');
  return shape.length > 0 ? `shape:${shape}` : undefined;
}

/**
 * Flattens a Zod issue list, recursing into `invalid_union` members.
 *
 * `invalid_union` is the one issue kind whose diagnostic content is entirely
 * in its children: the parent says only "Invalid input", while the member
 * errors carry the real `expected`/path information - and, being full issue
 * lists of their own, they also carry their own `message` strings and their
 * own leak surface. Recursing here means the members go through the same
 * projection (and the same omissions) as any top-level issue instead of riding
 * out attached to the parent.
 *
 * Member paths are RELATIVE to the union's own path, so they are re-based onto
 * it during the walk. The union parent itself is kept as a row (code
 * `invalid_union`) so the tree structure is legible; its `errors` are not.
 */
function flattenIssues(
  issues: ReadonlyArray<unknown>,
  basePath: ReadonlyArray<PropertyKey>,
  depth: number,
  out: { issue: RawIssueLike; path: PropertyKey[] }[]
): void {
  for (const raw of issues) {
    if (!raw || typeof raw !== 'object') continue;
    const issue = raw as RawIssueLike;
    const path = [...basePath, ...(issue.path ?? [])];
    out.push({ issue, path });

    if (depth >= MAX_UNION_DEPTH) continue;

    const members = issue.errors ?? issue.unionErrors;
    if (!Array.isArray(members)) continue;

    for (const member of members) {
      // Zod v4: `errors` is issue[][]. Zod v3: `unionErrors` is ZodError[].
      const memberIssues: unknown = Array.isArray(member)
        ? member
        : (member as { issues?: unknown })?.issues;
      if (Array.isArray(memberIssues)) {
        flattenIssues(memberIssues, path, depth + 1, out);
      }
    }
  }
}

/**
 * Extracts the REDACTION SENTINELS a scrub pass produced over the issue
 * messages, and nothing else.
 *
 * The messages themselves never ship (see the privacy floor above). But the
 * fact that a message contained an email- or identifier-SHAPED substring is
 * itself worth knowing: it means some schema in this codebase has a custom
 * refinement interpolating payload data into its message, which is a defect to
 * go fix. Zod v4's built-in messages no longer interpolate the received VALUE,
 * but that is a narrower guarantee than it sounds: they still interpolate
 * payload-derived KEYS (executed: a failed `.strict()` object produces
 * `Unrecognized key: "authorization_token"`), and `ctx.addIssue({ message })`,
 * `.refine(fn, msg)` and any hand-written `error` callback interpolate whatever
 * their author wrote. Which is why NO message reaches an emitted field, built-in
 * or not - only the sentinels this function extracts do. This is a tell, not a
 * guarantee.
 *
 * What is emitted is only the sentinel token (`[EMAIL_REDACTED]`,
 * `[REDACTED]`), never the surrounding text. A message carrying a value the
 * scrubbers do NOT recognize - an API key shape, say - produces no sentinel and
 * so produces nothing at all, which is the correct fail-closed behavior: silence
 * beats shipping the unrecognized text on the chance it was harmless.
 */
function collectRedactionSignals(messages: string[]): string[] {
  const signals = new Set<string>();
  for (const message of messages) {
    if (!message) continue;
    const scrubbed = scrubSensitiveStrings(message);
    if (scrubbed === message) continue;
    for (const match of scrubbed.match(/\[[A-Z_]+\]/g) ?? []) {
      signals.add(match);
    }
  }
  return [...signals];
}

/** One flattened issue plus everything the retention sort needs to rank it. */
interface RetentionCandidate {
  issue: RawIssueLike;
  path: PropertyKey[];
  dotted: string;
  code: string;
  index: number;
  tier: number;
}

/**
 * Retention tier for one issue. Lower wins; ties break on declaration order.
 * See {@link projectSchemaIssues} for why the ordering is load-bearing.
 */
function retentionTier(schema: string | undefined, dotted: string, firstOfPair: boolean): number {
  if (isSafeFieldEnrolled(schema, dotted)) return 0;
  return firstOfPair ? 1 : 2;
}

/** Renders one retained issue as a FLAT row of primitives. */
function buildRow(
  { issue, path, dotted, code }: RetentionCandidate,
  input: unknown,
  schema: string | undefined
): ProjectedIssue {
  const value = valueAtPath(input, path);

  const row: ProjectedIssue = { path: dotted, code, received: typeNameOf(value) };

  // Everything the SCHEMA declared, folded into one field. Authored in .ts
  // source, scrubbed and bounded on the way out - see `composeExpected`.
  const expected = composeExpected(issue);
  if (expected !== undefined) {
    row.expected = expected;
  }

  // `unrecognized_keys` carries PAYLOAD-DERIVED key names. The names are
  // dropped outright; only how many there were survives, which is enough to
  // tell "the backend added a field" from "the client hit the wrong route".
  //
  // The count has its OWN key. It used to reuse `issueCount`, which meant one
  // event could carry `issueCount: 1` at the top level beside a row reading
  // `{ code: "unrecognized_keys", issueCount: 2 }` - three incompatible
  // meanings (total / key count / truncation total) on one name, and an
  // operator reading them side by side gets a wrong answer, not a confusing
  // one. `issueCount` now means "true issue total" everywhere it appears.
  if (code === 'unrecognized_keys' && Array.isArray(issue.keys)) {
    row.key_count = issue.keys.length;
  }

  // A `custom` issue is otherwise indistinguishable from every other custom
  // issue at the same path. See `describeCustomIssue` for why the message
  // itself still never ships.
  if (code === 'custom') {
    const issueCode = describeCustomIssue(
      issue,
      (issue as { message?: unknown }).message as string | undefined
    );
    if (issueCode !== undefined) {
      row.issueCode = issueCode;
    }
  }

  // Explicitly enrolled, human-reviewed fields may carry shape descriptors.
  // Every other field gets nothing - `describeSafeField` returns null.
  const descriptor = describeSafeField(schema, dotted, value);
  if (descriptor) {
    Object.assign(row, descriptor);
  }

  return row;
}

/**
 * Projects a ZodError into the bounded, value-free form that is safe to send.
 *
 * ROW RETENTION IS BY DIAGNOSTIC PRIORITY, AND THAT ORDERING IS LOAD-BEARING.
 * Truncation used to be `flattened.slice(0, limit)` - first N in Zod
 * DECLARATION order - which silently dropped the field that mattered from BOTH
 * emitted surfaces. Reproduced by drifting every field of the REAL
 * `colonelOrganizationDetailRecordSchema` at once: it declares 25 fields and
 * `record.subscription_period_end` is the 21st, so the first ten rows in key
 * order stop at `record.owner_id` and the field was absent from `issues` AND
 * from the `schemaField` tag. A search for "every event where
 * record.subscription_period_end failed" returned zero hits during exactly the
 * scenario this branch exists for - a mixed-version rollout where the whole
 * response drifts at once. Against the pre-change code, which put every issue
 * in extras, that was a regression.
 *
 * That ordinal is stated because it was executed, not because it has to stay
 * right: an earlier version of this comment said "field #12", which was wrong,
 * and the same wrong number was corrected once already in
 * `safeFieldRegistry.ts`. Both ordinals drift as the schema grows, so the
 * guarantee is pinned by execution instead - `safeFieldRetention.spec.ts`
 * drifts every field of that live schema and asserts the enrolled row
 * survives. No number in this docblock has to be right for tier 0 to hold.
 *
 * The rule, in tiers, ties broken by declaration order:
 *
 *   0. the `(schema, path)` pair is enrolled in `safeFieldRegistry`. Enrollment
 *      is a human writing down "these failures are the ones worth reading", so
 *      an enrolled row is retained unconditionally.
 *   1. first occurrence of a distinct `(path, code)` pair - breadth over the
 *      failure surface.
 *   2. repeats of a pair already represented - a 200-element array failing the
 *      same way at every index says nothing the first row did not.
 *
 * Survivors are then re-sorted back into declaration order for emission, so
 * the rows still read top-to-bottom like the schema.
 *
 * `paths` is built from the FULL issue list in that same priority order and
 * gets its OWN, larger cap ({@link MAX_PROJECTED_PATHS}) - it feeds the one
 * indexed tag, and priority order means the field that matters survives the
 * consumer's 200-character cut.
 *
 * @param error - The ZodError produced by `safeParse`.
 * @param input - The data that failed to parse. Inspected for TYPE NAMES and,
 *   for registry-enrolled fields only, shape descriptors. Never emitted.
 * @param schema - The caller's context/schema name. Used as the registry key
 *   half and echoed by the caller as the `schema` tag.
 * @param limit - Row cap. Defaults to {@link MAX_PROJECTED_ISSUES}.
 */
export function projectSchemaIssues(
  error: z.ZodError,
  input: unknown,
  schema?: string,
  limit: number = MAX_PROJECTED_ISSUES
): SchemaIssueProjection {
  const flattened: { issue: RawIssueLike; path: PropertyKey[] }[] = [];
  flattenIssues((error.issues ?? []) as ReadonlyArray<unknown>, [], 0, flattened);

  const issueCount = flattened.length;

  const seenPairs = new Set<string>();
  const candidates: RetentionCandidate[] = flattened.map(({ issue, path }, index) => {
    const dotted = joinPath(path);
    const code = typeof issue.code === 'string' ? issue.code : 'unknown';
    // Array INDICES are collapsed for the distinctness key only. `items.0.v`
    // and `items.11.v` are different paths but the same FAILURE, and a 200
    // -element array failing identically at every index would otherwise fill
    // the whole row budget with one restatement and evict the field that
    // genuinely differs. The emitted path keeps its real index.
    const pair = `${dotted.replace(/(^|\.)\d+(?=\.|$)/g, '$1*')}\u0000${code}`;
    const firstOfPair = !seenPairs.has(pair);
    seenPairs.add(pair);

    return { issue, path, dotted, code, index, tier: retentionTier(schema, dotted, firstOfPair) };
  });

  const byPriority = [...candidates].sort((a, b) => a.tier - b.tier || a.index - b.index);

  const truncated = issueCount > limit;
  const kept = byPriority.slice(0, limit).sort((a, b) => a.index - b.index);

  const rows: ProjectedIssue[] = kept.map((candidate) => buildRow(candidate, input, schema));

  if (truncated) {
    // Truncation is reported as a SENTINEL ROW rather than a new top-level key
    // so the emitted key vocabulary stays inside the approved set (`path`,
    // `code`, `issueCount`) whether or not truncation happened. Self-describing
    // and allowlist-stable beats a bespoke boolean.
    rows.push({ path: ROOT_PATH, code: 'projection_truncated', issueCount });
  }

  const paths: string[] = [];
  for (const candidate of byPriority) {
    if (paths.length >= MAX_PROJECTED_PATHS) break;
    if (!paths.includes(candidate.dotted)) paths.push(candidate.dotted);
  }

  const messages = flattened
    .map(({ issue }) => (issue as { message?: unknown }).message)
    .filter((m): m is string => typeof m === 'string');

  return {
    rows,
    issueCount,
    truncated,
    paths,
    redactionSignals: collectRedactionSignals(messages),
  };
}
