// src/utils/redirect.ts

/**
 * Longest accepted redirect target; caps DoS surface on the decode below.
 * Exported so the parity spec pins the fixture's length-boundary cases against
 * THIS value, the way the Ruby spec reads RedirectPaths::MAX_PATH_LENGTH —
 * the two must stay equal or the shared fixture turns one suite red.
 */
export const MAX_REDIRECT_LENGTH = 2048;

/**
 * True when the string contains a C0 control character or DEL.
 *
 * Written as a char-code scan rather than a regex on purpose: a literal
 * /[\x00-\x1F\x7F]/ trips eslint's no-control-regex, and the escape-hatch
 * comment would then be load-bearing. Control characters matter because a
 * CR/LF smuggled into a redirect target can split a header or forge a second
 * request line once the value is echoed back by an intermediary.
 */
function hasControlChars(value: string): boolean {
  for (let i = 0; i < value.length; i += 1) {
    const code = value.charCodeAt(i);
    if (code <= 0x1f || code === 0x7f) return true;
  }
  return false;
}

/**
 * True when the value contains a literal `..` SEGMENT. Segment-wise, not a
 * substring scan: `/files/a..b` is a legitimate name, `/a/../b` and `/..` are
 * traversal.
 *
 * The whole string is split, query and fragment included — matching
 * RedirectPaths#traversal_segment? in lib/onetime/utils/redirect_paths.rb,
 * which splits on '/' without carving off `?`/`#` first. So `/a?next=/../b`
 * is rejected while a bare `/search?q=..` is not (it is not slash-delimited).
 * Carving the query off first would accept the former and break parity, and a
 * value one side stores that the other refuses is a silently broken journey.
 */
function hasDotDotSegment(value: string): boolean {
  return value.split('/').includes('..');
}

/**
 * The characters rejected in BOTH the raw and the once-decoded value: any
 * backslash (browsers normalize `\` to `/`, turning `/\evil.example` into a
 * protocol-relative URL) and any control character (header injection).
 */
function hasForbiddenChars(value: string): boolean {
  return value.includes('\\') || hasControlChars(value);
}

/**
 * Validates that a string is a safe INTERNAL redirect target.
 *
 * Security: prevents open-redirect and header-injection via the `?redirect=`
 * query param, which is user-controlled on every auth surface. The identical
 * ruleset is implemented server-side in Ruby (signup persists a validated
 * redirect and replays it on verify-account) — the two must stay in parity, so
 * change both or neither.
 *
 * That parity is ENFORCED, not merely requested here:
 * `tests/fixtures/redirect_path_cases.json` is a single accept/reject table
 * read by BOTH src/tests/utils/redirect.spec.ts and
 * spec/unit/onetime/utils/redirect_paths_spec.rb. Change a rule below and the
 * fixture goes with it — otherwise one of those two suites turns red.
 *
 * Rules:
 *  1. non-empty string, at most 2048 characters;
 *  2. starts with `/`, and the second character is neither `/` (protocol-
 *     relative → external host) nor `\` (browsers normalize `\` to `/`);
 *  3. no backslash, no `://`, and no control characters anywhere;
 *  4. percent-decoded ONCE, the value must not smuggle in a backslash, a
 *     control character, a leading `//`, or a `..` segment — encoding is how
 *     those get past a naive prefix check (`/%2f%2fevil.example`);
 *  5. query string and hash ride along untouched, so callers can hand the
 *     whole value to router.push and keep `?view=raw#content`.
 *
 * Ruby counterpart: Onetime::Utils::RedirectPaths#safe_internal_path?.
 *
 * @param path - candidate redirect target (raw query-param value)
 * @returns true if the path is a safe internal redirect
 */
export function isValidInternalPath(path: string | undefined | null): path is string {
  if (typeof path !== 'string' || path.length === 0 || path.length > MAX_REDIRECT_LENGTH) {
    return false;
  }

  // Must start with a single slash: '//evil.example' is a protocol-relative
  // authority, not a path. ('/\evil.example' is caught by the backslash scan.)
  if (!path.startsWith('/') || path[1] === '/') return false;

  if (path.includes('://') || hasForbiddenChars(path)) return false;

  // Decode exactly once. A malformed sequence ('%zz', a lone '%') throws —
  // treat it as invalid rather than guessing at the author's intent.
  let decoded: string;
  try {
    decoded = decodeURIComponent(path);
  } catch {
    return false;
  }

  return !hasForbiddenChars(decoded) && !decoded.startsWith('//') && !hasDotDotSegment(decoded);
}

/**
 * Static baseline allowlist for checkout origins.
 *
 * Contains only the shared Stripe Checkout host. When a Stripe "custom domain"
 * is configured on the account, its host is NOT hardcoded here — it is supplied
 * at runtime from the bootstrap `checkout_host` config via
 * setAllowedCheckoutHost(). See isAllowedCheckoutUrl.
 *
 * Do NOT loosen these to a wildcard `*.stripe.com` or `*.onetimesecret.com`.
 */
const CHECKOUT_ALLOWED_ORIGINS = ['https://checkout.stripe.com'] as const;

let configuredCheckoutOrigin: string | null = null;

/**
 * Bare-host shape for a Stripe custom Checkout domain: DNS labels with an
 * optional `:port` and nothing else — no scheme, userinfo, path, query, or
 * fragment. Mirrors CHECKOUT_HOST_RE in lib/onetime/billing_config.rb so a
 * value that boots on the backend also passes here at navigation time. The
 * captured group is the optional port digits, range-checked by the caller.
 */
const CHECKOUT_HOST_RE =
  /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)(?:\.(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?))*(?::(\d{1,5}))?$/i;

/**
 * Register this deployment's Stripe custom-domain Checkout host (bare host,
 * e.g. "pay.onetimesecret.com"), sourced from the bootstrap `checkout_host`
 * config. Call once at app init. Empty/invalid input clears it. Enables
 * isAllowedCheckoutUrl to accept live-mode Checkout URLs served from the
 * account's Stripe custom domain without hardcoding the host.
 *
 * Input must be a bare host (optionally `host:port`). Surrounding whitespace is
 * tolerated (env/helm values often carry it). Anything else — userinfo, a path,
 * a query/fragment, or an embedded scheme — is rejected rather than coerced,
 * because `new URL()` silently absorbs those components and could yield an
 * unintended origin (e.g. "pay.example.com@evil.example" → "https://evil.example",
 * or "https://pay.example.com" → host "https"). Rejection fails closed.
 */
export function setAllowedCheckoutHost(host: string | undefined | null): void {
  // Default to cleared; only a well-formed bare host re-enables the origin.
  configuredCheckoutOrigin = null;
  if (!host) return;

  const trimmed = host.trim();
  if (!trimmed) return;

  // Validate the raw input directly against a bare-host shape — DNS labels plus
  // an optional port, nothing else. This mirrors the backend CHECKOUT_HOST_RE in
  // lib/onetime/billing_config.rb. We deliberately do NOT validate by comparing
  // against `new URL().host`: that parser normalizes the default port (:443)
  // away, so the supported "host:443" form would fail the comparison and clear
  // the origin. The regex rejects userinfo, paths, queries, fragments, and
  // embedded schemes up front, so URL parsing below is only used to normalize.
  const match = CHECKOUT_HOST_RE.exec(trimmed);
  if (!match) return;

  const port = match[1];
  if (port !== undefined) {
    const portNum = Number(port);
    // new URL() rejects out-of-range ports; enforce the TCP range here so a
    // value like "pay.example.com:99999" fails closed at config time rather
    // than passing our shape check and then being silently dropped by new URL().
    if (portNum < 1 || portNum > 65535) return;
  }

  try {
    // Normalize to an origin (drops the default :443, lowercases the host).
    configuredCheckoutOrigin = new URL(`https://${trimmed}`).origin;
  } catch {
    // Unparseable despite matching the bare-host shape — leave cleared.
  }
}

/**
 * Validates that a checkout URL is safe to navigate to via `window.location`.
 *
 * Security (M-9): `checkout_url` is API-derived and assigned directly to
 * `window.location.href` in the billing plan flow. Restrict navigation to the
 * Stripe Checkout host or the app's own origin so a tampered/unexpected value
 * cannot drive an open redirect. isValidInternalPath — this module's other
 * validator — only permits same-origin internal PATHS, so an external-host
 * allowlist requires this dedicated helper.
 *
 * The host allowlist is intentionally exact. Accepted origins are:
 *   1. the static baseline: the shared `checkout.stripe.com` host,
 *   2. the current app origin (same-origin), and
 *   3. this deployment's runtime-configured Stripe custom-domain Checkout host,
 *      seeded once at app init from the bootstrap `checkout_host` config via
 *      setAllowedCheckoutHost() (e.g. `pay.onetimesecret.com`).
 *
 * Do NOT loosen to a wildcard `*.stripe.com` or `*.onetimesecret.com`.
 *
 * @param url - The checkout URL to validate
 * @returns true only when the URL parses and its origin is an allowlisted
 *          Stripe Checkout host, the current origin, or the configured host
 */
export function isAllowedCheckoutUrl(url: string | undefined | null): url is string {
  if (!url || typeof url !== 'string') return false;
  try {
    const { origin } = new URL(url);
    return (
      (CHECKOUT_ALLOWED_ORIGINS as readonly string[]).includes(origin) ||
      origin === window.location.origin ||
      (configuredCheckoutOrigin !== null && origin === configuredCheckoutOrigin)
    );
  } catch {
    return false;
  }
}
