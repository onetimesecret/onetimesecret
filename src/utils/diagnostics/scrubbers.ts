// src/utils/diagnostics/scrubbers.ts
//
// LAYER RULE: src/utils/diagnostics/ is pure policy — it must not import from
// `@sentry/*` nor from `src/plugins/`.
//
// Dependency-free utilities for scrubbing sensitive data from strings and URLs.
// It lives at this layer BECAUSE it is pure: the Sentry wiring in
// `src/plugins/core/` consumes it, and three modules under `src/utils/` do too,
// so the dependency has to point down. It was in the plugin directory before
// this branch, which made the util layer import upward.
//
// Used by:
// - axios interceptors (breadcrumb scrubbing)
// - Sentry beforeBreadcrumb handler
// - Sentry beforeSend handler
// - the schema-issue projection (`@/utils/diagnostics/schemaIssueProjection`)

import { scrubSensitivePath } from '@/generated/sentry-scrub-patterns';

/**
 * Legacy fallback pattern for sensitive URL paths.
 *
 * Current approach uses deterministic route metadata (fail-safe, opt-out):
 * - Frontend: src/routes/index.ts route definitions with scrub metadata
 * - Backend: Otto routes with `sensitive=true` annotation, e.g.:
 *   `GET /receipt/:identifier ... sensitive=true`
 *
 * This regex catches paths missed by route-derived patterns:
 * - /secret/, /private/, /receipt/, /incoming/ - core secret paths
 * - /invite/ - invitation tokens
 * - /confirm/ - email confirmation tokens
 *
 * @see scrubSensitivePath - generated patterns from route metadata
 * @see src/generated/sentry-scrub-patterns.ts - generated output
 * @internal Exported for testing
 */
export const SENSITIVE_PATH_PATTERN =
  /\/(secret|private|receipt|incoming|invite|confirm)\/([a-zA-Z0-9]+)/gi;

/**
 * Fallback pattern for verifiable identifiers appearing in unexpected paths
 * or free text. Matches both the current 62-char base-36 IDs (v0.24) and the
 * legacy 31-char IDs (v0.23). Routers/backend define verifiable identifiers as
 * base-36 (`[0-9a-z]`).
 *
 * Anchoring is asymmetric BY DESIGN:
 *   - The 62-char branch is UNANCHORED so a secret glued to adjacent word
 *     characters (`?ref=<id>abc`, `<id>x`, `load <id>_meta`) is still caught.
 *     A `\b`-anchored 62 branch silently leaked all of those shapes. The
 *     over-redaction risk is minimal: no ops-useful token is >= 62 chars, and
 *     partially redacting a longer blob is fail-safe, not a bug.
 *   - The 31-char branch stays `\b`-anchored and length-exact so ops-useful
 *     values of nearby lengths — trace IDs (32 hex), commit hashes (40 hex) —
 *     survive untouched; an unanchored 31 branch would match inside them.
 *
 * DOCUMENTED DIVERGENCE FROM BACKEND (by design, not drift):
 *   Frontend: /(?:[0-9a-z]{62}|\b[0-9a-z]{31}\b)/gi  (case-INSENSITIVE)
 *   Backend:  /(?:[0-9a-z]{62}|\b[0-9a-z]{31}\b)/    (case-SENSITIVE)
 *     — lib/onetime/initializers/setup_diagnostics.rb IDENTIFIER_TEXT_PATTERN
 *   Anchoring now matches (62 branch unanchored, 31 branch \b-anchored on
 *   both sides); the only remaining divergence is case-sensitivity.
 *
 * The backend stays strict (lowercase-only) because it controls its own
 * identifier generation and wants to avoid redacting mixed-case ops tokens.
 * The frontend is deliberately case-insensitive: it scrubs data from browser
 * URLs/messages of unknown provenance, so it errs toward over-redaction.
 *
 * @internal Exported for testing
 */
export const VERIFIABLE_ID_PATTERN = /(?:[0-9a-z]{62}|\b[0-9a-z]{31}\b)/gi;

/**
 * Query-parameter names whose VALUES carry secrets and must be redacted.
 * Mirrors the backend SENSITIVE_QUERY_PARAMS list.
 *   — lib/onetime/initializers/setup_diagnostics.rb SENSITIVE_QUERY_PARAMS
 *
 * @internal Exported for testing
 */
export const SENSITIVE_QUERY_PARAMS = ['key', 'secret', 'token', 'passphrase'] as const;

/**
 * Pattern for email addresses in free text, query values and URLs.
 *
 * MIRROR — this pattern and its `[EMAIL_REDACTED]` sentinel are duplicated
 * verbatim as EMAIL_PATTERN in
 * lib/onetime/initializers/setup_diagnostics.rb. The two must change
 * TOGETHER, in the same commit: a Sentry payload can be assembled by either
 * half, so a widening applied to only one half still leaks. The only
 * permitted difference is the flags — JS needs `u` to enable `\p{...}` and
 * `g` for replace-all; Ruby needs neither. The source between the delimiters
 * is byte-identical, and tests/fixtures/email_redaction_corpus.json is run
 * through both to prove it.
 *
 * SUPERSET-OF-THE-VALIDATOR INVARIANT: whatever the validator accepts is
 * storable, so every redactor must be at least as wide as the validator
 * (Truemail's REGEX_EMAIL_PATTERN), which allows `\p{L}` on BOTH sides of the
 * `@` and a `\p{L}{2,63}` TLD. The former ASCII-only class matched none of
 * `josé@example.com`, `用户@example.com`, `user@пример.рф` — all storable —
 * so they reached Sentry in the clear. Hence:
 *   - local part: `[\p{L}\p{N}._%+'-]`
 *   - host:       `[\p{L}\p{N}.\p{Pd}]`  (\p{Pd} subsumes ASCII '-'; Truemail
 *                                        admits non-ASCII dashes in a label)
 *   - TLD:        `\p{L}{2,}`            (IDN TLDs: .рф, .онлайн)
 * `\p{N}` is deliberately NOT allowed in the TLD so `1.2@3.4` survives and
 * version/coordinate strings stay readable for operators.
 *
 * `u` is required for `\p{...}`; it also makes the pattern reject the
 * malformed escapes ECMAScript would otherwise tolerate. `g` is load-bearing
 * for `String#replace` (replace-all) — `lastIndex` is reset by `replace`, but
 * any direct `.test()`/`.exec()` in a test must reset it explicitly.
 *
 * No atomic group here (ECMAScript cannot express one), matching the backend:
 * every quantifier is a single pass over a character class with a literal
 * (`@`, `.`) separating it from the next, so the worst case is polynomial,
 * not exponential.
 *
 * @internal Exported for testing
 */
export const EMAIL_PATTERN = /[\p{L}\p{N}._%+'-]+@[\p{L}\p{N}.\p{Pd}]+\.\p{L}{2,}/gu;

// ═══════════════════════════════════════════════════════════════════════════════
// OPAQUE-IDENTIFIER NETS
// ═══════════════════════════════════════════════════════════════════════════════
//
// These run over exception messages, breadcrumb messages, URLs and — since the
// schema-issue projection routes every emitted field path through
// `scrubSensitiveStrings` — over record keys that may have come off the wire.
//
// THE DESIGN CONSTRAINT IS SYMMETRIC. Under-scrubbing leaks a tenant, customer
// or credential reference into an indexed field on an event sent to Sentry.
// OVER-scrubbing is just as much a defect: these same functions run over stack
// frames, module paths, version strings and schema field names, and a net that
// eats those degrades every event on the platform rather than one. So every net
// below is (a) anchored, (b) restricted to a KNOWN prefix or a KNOWN literal
// shape, and (c) required to carry evidence of being machine-generated — a
// digit, an uppercase character, or an exact length — before it fires.
//
// Each net gets its OWN sentinel. A reader triaging an event needs to know
// WHAT was removed, not merely that something was; the projection also
// collects sentinel tokens as `redactionSignals`, so a sentinel is a
// diagnostic output in its own right. All sentinels obey the whitespace-free
// `/^\[[A-Z_]+\]$/` invariant documented on `scrubSensitiveStrings`.

/**
 * Credential-bearing prefixes. Stripe uses `sk_`/`pk_`/`rk_` for API keys and
 * `whsec_` for webhook signing secrets; all four denote key MATERIAL, not an
 * object reference, so the body class is deliberately loose (underscores
 * included) and no digit is required — `sk_live_SUPER_SECRET` must die whole.
 *
 * Case-sensitive lowercase prefix, `\b`-anchored: this cannot match inside a
 * sentinel (`[SECRET_REDACTED]`), a SCREAMING_CASE constant, or a word ending
 * in `sk`/`pk` (`risk_score` has no boundary before `sk`).
 *
 * @internal Exported for testing
 */
export const PREFIXED_SECRET_PATTERN = /\b(?:whsec|sk|pk|rk)_[0-9a-zA-Z_]{6,}/g;

/**
 * Prefixed opaque object ids: `org_9f3a2b1c8d7e6f50`, `cus_NffrFeUfNV2Hib`,
 * `sub_1P…`. The prefix list is drawn from what this codebase actually
 * handles — Stripe object prefixes referenced in src/schemas (`cus_`, `prod_`,
 * `price_`, `sub_`) and the collection names the API route surface
 * parameterizes — rather than from a guess at what an id could look like.
 *
 * TWO GUARDS keep this off ordinary identifiers, both proven necessary against
 * real names in this tree:
 *
 *   1. length — the body must be >= 6 alphanumerics, which spares `org_id`.
 *   2. entropy evidence — the body must contain a DIGIT or an UPPERCASE
 *      letter. Without this guard the net eats `org_context`
 *      (colonel-sessions.ts), `price_formatted` (billing.ts),
 *      `price_metadata` / `price_nickname` (colonel.ts) and `sub_total` —
 *      i.e. schema field names, which are the diagnostic payload this whole
 *      branch exists to preserve.
 *
 * `subscription_period_end` is unreachable for a different reason: `sub` must
 * be followed immediately by `_`, and here it is followed by `s`.
 *
 * @internal Exported for testing
 */
export const PREFIXED_ID_PATTERN =
  /\b(?:price|prod|acct|card|cust|sess|seti|txn|org|cus|sub|evt|inv|dom|mem|usr|tok|req|src|pm|po|ch|cs|pi|si|ba)_(?=[0-9a-zA-Z]{6,})(?=[0-9a-zA-Z]*[0-9A-Z])[0-9a-zA-Z]+/g;

/**
 * Onetime Secret external identifiers. `feature :external_identifier` declares
 * `format:` per model — `ur%<id>s` (Customer), `cd%<id>s` (CustomDomain),
 * `on%<id>s` (Organization) — over a 128-bit value encoded as EXACTLY 25
 * base36 characters (familia/lib/familia/features/external_identifier.rb).
 * So the wire shape is a two-letter prefix plus 25 lowercase base36 chars.
 *
 * Length-exact and `\b`-anchored on both sides, lowercase-only to match
 * generation. A 27-character lowercase alphanumeric run is not a word, a
 * version, or a route segment, so the false-positive surface is empty; the
 * existing 62/31-char `VERIFIABLE_ID_PATTERN` does not reach this length.
 *
 * @internal Exported for testing
 */
export const OTS_EXTID_PATTERN = /\b(?:ur|cd|on)[0-9a-z]{25}\b/g;

/**
 * RFC 4122 UUID in its canonical hyphenated form.
 *
 * DELIBERATELY NOT MATCHING THE BARE 32-HEX FORM. A bare 32-hex run is
 * byte-identical to a W3C/Sentry `trace_id`, which this codebase emits on
 * purpose and an operator needs in order to join a frontend event to its
 * backend transaction; a 40-hex run is a git commit. Both are ops-useful and
 * neither is personal data, so the hyphens are load-bearing evidence here.
 * Bare-hex identifiers appearing as a PATH SEGMENT are handled upstream by
 * `parameterizeApiPath`, which is segment-anchored and can afford to be
 * greedier than a free-text net can.
 *
 * @internal Exported for testing
 */
export const UUID_PATTERN =
  /\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/g;

/** One octet, range-validated: 0-255 and nothing wider. */
const IPV4_OCTET = '(?:25[0-5]|2[0-4]\\d|1\\d{2}|[1-9]?\\d)';

/**
 * IPv4 literal. Octets are RANGE-validated (not `\d{1,3}`) and the whole match
 * is fenced by `(?<![\w.])` / `(?![\w.])`, which is what keeps version and
 * build strings intact:
 *
 *   `10.0.19041.1`  — `19041` is not an octet, and the lookbehind forbids
 *                     restarting mid-number, so NOTHING matches.
 *   `v1.2.3-rc.4`   — three parts; the lookbehind also blocks the `1.2.3` run
 *                     because `v` is a word character.
 *   `1.2.3.4.5`     — the trailing `(?![\w.])` rejects it, and no later start
 *                     offset is legal.
 *
 * The residual ambiguity is a genuine four-part dotted version whose every
 * component is 0-255. That shape is indistinguishable from an address by
 * inspection, and this net resolves the tie toward redaction.
 *
 * @internal Exported for testing
 */
export const IPV4_PATTERN = new RegExp(
  `(?<![\\w.])(?:${IPV4_OCTET}\\.){3}${IPV4_OCTET}(?![\\w.])`,
  'g'
);

/**
 * Addresses that identify a MACHINE ROLE rather than a person, and are worth
 * more to an operator than they cost in privacy: loopback (`redis://127.0.0.1
 * :6379/0` is a configuration string, not a client), the unspecified address,
 * and the broadcast address. Everything else — including RFC1918 space, which
 * in a self-hosted deployment is exactly where real client addresses live — is
 * redacted.
 */
const NON_PERSONAL_IPV4 = /^(?:127\.\d{1,3}\.\d{1,3}\.\d{1,3}|0\.0\.0\.0|255\.255\.255\.255)$/;

/**
 * IPv6 literal, in the full eight-group form or a `::`-compressed form.
 *
 * THREE RESTRICTIONS, each earned:
 *
 *   1. LOWERCASE ONLY. `Db::add` and `Cafe::Face` are Ruby constant paths, and
 *      Ruby stack frames are a primary input to this function. Requiring
 *      lowercase eliminates the CamelCase scope-operator collision outright.
 *   2. A DIGIT IS REQUIRED (`(?=[0-9a-f:]*\d)`). Real addresses carry one
 *      (`2001:db8::1`, `fe80::1`); an all-letter token like `bad::face` does
 *      not, and survives.
 *   3. The compressed branch REQUIRES `::`. A clock time (`12:34:56`) has no
 *      doubled colon and only three groups, so it is out of reach of both
 *      branches.
 *
 * @internal Exported for testing
 */
export const IPV6_PATTERN =
  /\b(?=[0-9a-f:]*\d)(?:[0-9a-f]{1,4}:){7}[0-9a-f]{1,4}\b|\b(?=[0-9a-f:]*\d)(?:[0-9a-f]{1,4}:){1,7}:(?:[0-9a-f]{1,4}(?::[0-9a-f]{1,4})*)?/g;

/**
 * Applies every opaque-identifier net, in the one order that composes.
 *
 * ORDERING IS LOAD-BEARING:
 *   - credentials before object ids, so a `sk_`/`pk_` body is consumed whole
 *     rather than half-eaten by a narrower net;
 *   - IPv6 before IPv4, so an IPv4-mapped address is not split;
 *   - all of these AFTER the email pass and BEFORE the 62/31-char verifiable
 *     -id pass, preserving the existing ordering invariants at both ends.
 *
 * Every sentinel emitted here is whitespace-free and uppercase, so the
 * downstream path patterns (`[^/\s]+`) never split one mid-token.
 *
 * @param text - Already email-scrubbed text.
 * @returns The text with opaque identifiers replaced by their sentinels.
 */
function scrubOpaqueIdentifiers(text: string): string {
  let result = text;
  result = result.replace(PREFIXED_SECRET_PATTERN, '[SECRET_REDACTED]');
  result = result.replace(PREFIXED_ID_PATTERN, '[ID_REDACTED]');
  result = result.replace(OTS_EXTID_PATTERN, '[EXTID_REDACTED]');
  result = result.replace(UUID_PATTERN, '[UUID_REDACTED]');
  result = result.replace(IPV6_PATTERN, '[IP_REDACTED]');
  result = result.replace(IPV4_PATTERN, (match) =>
    NON_PERSONAL_IPV4.test(match) ? match : '[IP_REDACTED]'
  );
  return result;
}

/**
 * Scrubs sensitive data from arbitrary strings using regex patterns.
 * Used for exception messages, standalone messages, and other text.
 *
 * Scrubs:
 * - Email addresses -> [EMAIL_REDACTED]
 * - Credential-prefixed keys (sk_/pk_/rk_/whsec_) -> [SECRET_REDACTED]
 * - Prefixed opaque object ids (org_/cus_/sub_/...) -> [ID_REDACTED]
 * - Onetime Secret external ids (ur…/cd…/on… + 25 base36) -> [EXTID_REDACTED]
 * - Hyphenated UUIDs -> [UUID_REDACTED]
 * - IPv4 / IPv6 literals -> [IP_REDACTED]
 * - 62/31-char verifiable IDs -> [REDACTED]
 * - Sensitive path patterns -> /type/[REDACTED]
 *
 * DISTINCT SENTINEL PER NET, on purpose. `[REDACTED]` everywhere would tell a
 * reader that something vanished but not what kind of thing, and the schema
 * -issue projection surfaces the sentinel set as `redactionSignals` — a
 * diagnostic output. The taxonomy is the payoff for the redaction.
 *
 * @param text - The string to scrub
 * @returns The scrubbed string with sensitive data replaced
 */
export function scrubSensitiveStrings(text: string): string {
  if (!text || typeof text !== 'string') {
    return text;
  }

  let result = text;

  // Scrub email addresses.
  //
  // Invariant: every sentinel emitted by any pass here must be whitespace
  // -free (matches /^\[[A-Z_]+\]$/). Later passes apply path-scrub patterns
  // using the `[^/\s]+` value class, which stops at any whitespace inside a
  // preceding sentinel. A sentinel like `[EMAIL REDACTED]` (with a literal
  // space) would cause the path regex to split its capture mid-sentinel,
  // producing cosmetically-corrupted output like `[REDACTED] REDACTED]`.
  // The data is still scrubbed, but the sentinels stop composing cleanly.
  // Keep all sentinel tokens square-bracketed, uppercase, underscored.
  result = result.replace(EMAIL_PATTERN, '[EMAIL_REDACTED]');

  // Scrub credentials, prefixed ids, extids, UUIDs and IP literals. Runs after
  // the email pass (an ID-shaped local part must not be eaten first) and
  // before the verifiable-id pass (whose 62-char branch is unanchored and
  // would otherwise chew into a longer prefixed blob).
  result = scrubOpaqueIdentifiers(result);

  // Scrub 62-char verifiable IDs
  result = result.replace(VERIFIABLE_ID_PATTERN, '[REDACTED]');

  // Scrub sensitive path patterns using generated route-derived patterns
  result = scrubSensitivePath(result);

  // Fallback: scrub any remaining sensitive paths not covered by generated patterns
  result = result.replace(SENSITIVE_PATH_PATTERN, '/$1/[REDACTED]');

  return result;
}

/**
 * Apply generated patterns to the pathname portion of a URL.
 *
 * The generated patterns are unanchored, so applying them directly to a full
 * URL would pull the query string into the capture group — the value class
 * `[^/\s]+` does not stop at `?` or `#`. This function parses the input
 * through `URL` (using a synthetic base for bare paths), scrubs only
 * `parsed.pathname`, and reassembles protocol + host + scrubbed path +
 * search + hash. Query params and fragments are preserved verbatim so they
 * can still drive breadcrumb-level debugging.
 *
 * Note: `scrubSensitiveStrings` intentionally applies the same patterns
 * directly to free-form text, where the whitespace boundary causes any
 * embedded `?foo=bar#frag` suffix to be redacted along with the identifier.
 * That over-scrubbing is a fail-safe, not a bug: a sensitive value leaking
 * into a query string inside an exception message should go away with the
 * rest of the URL.
 */
function extractAndScrubPath(input: string): string {
  try {
    // Use a synthetic base so bare paths (e.g. /api/v1/secret/abc?foo=bar)
    // parse cleanly. The base is discarded when reassembling — we only use
    // its parser. Detect "had host" by checking the raw input for a protocol
    // prefix, since `new URL('/p', 'http://_')` yields host `_` which we must
    // not echo back.
    //
    // Protocol-relative URLs (`//host/path`) are detected alongside
    // fully-qualified URLs so the host is preserved during reassembly.
    // Removing the `startsWith('//')` branch would cause such URLs to
    // silently drop their host. Adding it must also preserve the `//`
    // prefix on output (do not echo back the synthetic `http:` scheme
    // from the base URL).
    //
    // data: URIs (`data:text/plain,foo`) are not a real Sentry breadcrumb
    // input shape and are not accounted for. Under current logic they
    // would have their scheme stripped because the scheme regex requires
    // `://`.
    const isProtocolRelative = input.startsWith('//');
    const isFullURL = /^[a-z][a-z0-9+.-]*:\/\//i.test(input);
    const hadHost = isProtocolRelative || isFullURL;
    const parsed = new URL(input, 'http://_');
    const scrubbedPath = scrubSensitivePath(parsed.pathname);

    // Reassemble the query/fragment from the RAW input, not from
    // `parsed.search`/`parsed.hash`. The URL serializer percent-encodes every
    // non-ASCII byte it round-trips, so `?email=user@пример.рф` comes back as
    // `?email=user@mail.%D0%BF...` — and the later EMAIL_PATTERN pass cannot
    // match a percent-encoded host, so an IDN address rode out to Sentry in
    // the clear. The backend twin (`scrub_url` in setup_diagnostics.rb) gsubs
    // the raw string and has never had this blind spot; slicing the raw suffix
    // is what keeps the two halves agreeing, and it is what this function's
    // contract already claimed ("preserved verbatim").
    const suffixIndex = input.search(/[?#]/);
    const rawSuffix = suffixIndex === -1 ? '' : input.slice(suffixIndex);

    if (!hadHost) return scrubbedPath + rawSuffix;
    const prefix = isProtocolRelative ? '//' : parsed.protocol + '//';
    return prefix + parsed.host + scrubbedPath + rawSuffix;
  } catch {
    // Fallback for genuinely malformed inputs (e.g. control chars that the
    // URL parser rejects even with a base).
    return scrubSensitivePath(input);
  }
}

/**
 * Redacts the VALUES of sensitive query parameters within a raw query string,
 * preserving the parameter names. Operates on a query string (not a full URL),
 * with or without a leading `?` — Sentry stores span `http.query` as
 * `parsedUrl.search`, which INCLUDES the leading `?` (@sentry/core fetch
 * instrumentation), while `scrubUrlQueryParamNames` passes the portion after
 * `?`. A leading `?` is stripped before splitting (so `?token=x` matches the
 * `token` param, not a bogus `?token` name) and preserved in the output so the
 * value round-trips faithfully.
 *
 * Matching is case-insensitive on the parameter NAME only (mirrors the backend
 * `SENSITIVE_QUERY_PARAMS.include?(key.downcase)`). Empty trailing segments are
 * preserved by keeping the raw split, so `a=1&` round-trips.
 *
 * @param query - Raw query string, e.g. `key=abc&foo=bar` or `?key=abc&foo=bar`
 * @returns The query string with sensitive param values replaced by [REDACTED]
 */
export function scrubSensitiveQueryParams(query: string): string;
export function scrubSensitiveQueryParams(query: null | undefined): null | undefined;
export function scrubSensitiveQueryParams(
  query: string | null | undefined
): string | null | undefined {
  if (!query) {
    return query;
  }

  const hasLeadingQuestionMark = query.startsWith('?');
  const bareQuery = hasLeadingQuestionMark ? query.slice(1) : query;

  const sensitive = SENSITIVE_QUERY_PARAMS as readonly string[];
  const scrubbed = bareQuery
    .split('&')
    .map((param) => {
      const eq = param.indexOf('=');
      if (eq === -1) {
        return param;
      }
      const name = param.slice(0, eq);
      if (sensitive.includes(name.toLowerCase())) {
        return `${name}=[REDACTED]`;
      }
      return param;
    })
    .join('&');
  return hasLeadingQuestionMark ? `?${scrubbed}` : scrubbed;
}

/**
 * Scrubs a query string (Sentry span `http.query` data, stored as
 * `parsedUrl.search` WITH its leading `?`): first redacts sensitive param
 * values by name (A1), then applies the verifiable-ID and email pattern nets
 * to anything remaining. Distinct from `scrubUrlWithPatterns`, which expects
 * a URL/path, not a query string.
 *
 * @param query - Raw query string, e.g. `?token=abc&email=user@x.com`
 * @returns The scrubbed query string (leading `?` preserved if present)
 */
export function scrubQueryStringValues(query: string): string;
export function scrubQueryStringValues(query: null | undefined): null | undefined;
export function scrubQueryStringValues(
  query: string | null | undefined
): string | null | undefined {
  if (!query) {
    return query;
  }
  let result = scrubSensitiveQueryParams(query);
  // Ordering invariant: the email pass must run BEFORE the identifier pass.
  // An ID-shaped local part (e.g. <62-char-id>@example.com) would otherwise
  // be replaced first, leaving `[REDACTED]@domain` that EMAIL_PATTERN can no
  // longer match — leaking the email domain.
  result = result.replace(EMAIL_PATTERN, '[EMAIL_REDACTED]');
  // Same nets, same ordering, as the other two entrypoints. A span's
  // `http.query` is a separate surface from its URL — `?ip=203.0.113.5` or
  // `?customer=cus_Nffr…` reaches Sentry through here without ever passing
  // through `scrubUrlWithPatterns`.
  result = scrubOpaqueIdentifiers(result);
  result = result.replace(VERIFIABLE_ID_PATTERN, '[REDACTED]');
  return result;
}

/**
 * Applies `scrubSensitiveQueryParams` to the query portion of a full URL or
 * bare path, preserving the base and any `#fragment`. String-based (not `URL`)
 * to avoid re-encoding param values and to mirror the backend's manual split.
 */
function scrubUrlQueryParamNames(url: string): string {
  const qIndex = url.indexOf('?');
  if (qIndex === -1) {
    return url;
  }
  const base = url.slice(0, qIndex);
  const rest = url.slice(qIndex + 1);
  const hashIndex = rest.indexOf('#');
  const query = hashIndex === -1 ? rest : rest.slice(0, hashIndex);
  const fragment = hashIndex === -1 ? '' : rest.slice(hashIndex);
  return `${base}?${scrubSensitiveQueryParams(query)}${fragment}`;
}

/**
 * Scrubs sensitive identifiers from a URL path using regex patterns.
 * Used for HTTP breadcrumbs where we don't have route context.
 *
 * Scrubs:
 * - Known sensitive paths (/secret/, /private/, /receipt/, /incoming/, /invite/, /confirm/)
 * - Sensitive query-param VALUES by name (?key=, ?secret=, ?token=, ?passphrase=)
 * - 62-char and 31-char verifiable IDs
 * - Email addresses in query strings (e.g., ?email=user@example.com)
 * - Credentials, prefixed opaque ids, extids, UUIDs and IP literals
 *
 * @param url - The URL string to scrub
 * @returns The scrubbed URL with sensitive identifiers replaced by [REDACTED]
 */
export function scrubUrlWithPatterns(url: string): string {
  if (!url || typeof url !== 'string') {
    return url;
  }

  // First pass: scrub using generated route-derived patterns. Patterns are
  // unanchored but applied to `parsed.pathname` via `extractAndScrubPath` so
  // that the capture group never includes the query string or fragment.
  let result = extractAndScrubPath(url);

  // Second pass: fallback for paths not covered by generated patterns
  result = result.replace(SENSITIVE_PATH_PATTERN, '/$1/[REDACTED]');

  // Third pass: redact sensitive query-param values by name (?token=... etc.)
  result = scrubUrlQueryParamNames(result);

  // Fourth pass: scrub email addresses (e.g., in query params like
  // ?email=user@example.com). Ordering invariant: the email pass must run
  // BEFORE the identifier pass — an ID-shaped local part would otherwise be
  // replaced first, leaving `[REDACTED]@domain` that EMAIL_PATTERN can no
  // longer match.
  result = result.replace(EMAIL_PATTERN, '[EMAIL_REDACTED]');

  // Fifth pass: credentials, prefixed ids, extids, UUIDs and IP literals.
  //
  // Applied HERE and not only in `scrubSensitiveStrings` because breadcrumb
  // URLs are a first-class leak surface in their own right:
  // `/api/colonel/banned-ips/203.0.113.5` (AdminBannedIps.vue) is a real
  // request this app makes, and an xhr/fetch breadcrumb carries its url with
  // no route context to parameterize it. Same nets, same ordering rules.
  result = scrubOpaqueIdentifiers(result);

  // Sixth pass: scrub any remaining 62/31-char verifiable IDs
  result = result.replace(VERIFIABLE_ID_PATTERN, '[REDACTED]');

  return result;
}
