// src/apps/admin/utils/confirmHeader.ts

/**
 * Server-side destructive-action confirmation (#4326).
 *
 * The colonel API rejects a destructive verb unless the request carries an
 * identifier of the target in X-OTS-Confirm. A HEADER, not a query parameter:
 * these tokens are frequently PII (a target's email, an org name) and a query
 * string is logged by every default access-log format, kept in browser history,
 * and is a Referer-leak candidate. Percent-encoded so a non-ASCII token (an org
 * display name) survives the ISO-8859-1 header charset; the server decodes with
 * Rack::Utils.unescape.
 *
 * A `confirm` query or body parameter is NOT a fallback server-side. Sending one
 * would leak the token into logs and change nothing.
 */
export const CONFIRM_HEADER = 'X-OTS-Confirm';

/** Request headers carrying the confirmation token for one gated call. */
export function confirmHeaders(token: string): Record<string, string> {
  return { [CONFIRM_HEADER]: encodeURIComponent(token) };
}

/**
 * The confirmation token for an ACCOUNT-scoped verb: the email address, falling
 * back to the public id when the account has none.
 *
 * Mirrors `ColonelAPI::Logic::DestructiveAction#account_confirm_token` exactly —
 * the two must agree or every such call 403s. Returns undefined when neither is
 * available (an unloaded record), which callers treat as "do not open the
 * dialog" rather than sending a blank token.
 */
export function accountConfirmToken(
  account: { email?: string | null; extid?: string | null } | null | undefined
): string | undefined {
  return account?.email?.trim() || account?.extid?.trim() || undefined;
}

/**
 * The confirmation token for an ORGANIZATION-scoped verb: the display name,
 * falling back to the public id. Mirrors
 * `ColonelAPI::Logic::DestructiveAction#org_confirm_token`.
 */
export function orgConfirmToken(
  org: { display_name?: string | null; extid?: string | null } | null | undefined
): string | undefined {
  return org?.display_name?.trim() || org?.extid?.trim() || undefined;
}
