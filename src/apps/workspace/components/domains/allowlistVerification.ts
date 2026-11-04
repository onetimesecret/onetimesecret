// src/apps/workspace/components/domains/allowlistVerification.ts
//
// Verified state of a tenant SSO allowlist entry (#4734, RISK-2026-10-10-01).
//
// Tenant SSO creates an account only for an address inside a custom domain
// whose ownership the organization has proven, so an allowlist entry outside
// every proven domain creates no new accounts. The API is authoritative: a
// saved record includes `verified_email_domains` (the proven set) and
// `unverified_allowed_domains` (the saved entries outside it, judged by the
// same A-label, label-boundary comparison the sign-in gate uses). An entry
// added in the form but not yet saved is judged here the same way, after both
// names are converted to their A-label form through the URL parser; a name
// the parser rejects stays `unknown` until the save reports on it. When the
// record carries no verdict at all (hasProofVerdict: saved entries exist but
// the API listed none as proven or unverified), every entry is `unknown`,
// saved or not: the empty proven set is then not a judgment, and judging an
// unsaved entry against it would call it not proven under a headline that
// says ownership could not be checked.

export type AllowlistEntryState = 'verified' | 'unverified' | 'unknown';

export interface AllowlistVerificationContext {
  /** Entries of the saved record (`ssoConfig.allowed_domains`). */
  savedAllowedDomains: readonly string[];
  /** Saved entries the API judged outside every proven domain. */
  unverifiedAllowedDomains: readonly string[];
  /** The organization's proven domains, as the API serves them. */
  verifiedEmailDomains: readonly string[];
}

/**
 * A-label hostname for `name`, or null when the URL parser rejects it. The
 * WHATWG parser applies the same IDNA mapping the server's comparison key
 * round-trips through, so `bücher.example` and `xn--bcher-kva.example` agree.
 */
export function toALabel(name: string): string | null {
  const trimmed = name.trim();
  if (!trimmed || /[\s/?#@:\\]/.test(trimmed)) return null;
  try {
    const hostname = new URL(`https://${trimmed}`).hostname.replace(/\.$/, '');
    return hostname.length > 0 ? hostname : null;
  } catch {
    return null;
  }
}

/**
 * Whether `entry` equals, or lies below on a label boundary, one of
 * `verifiedEmailDomains`. null when `entry` cannot be converted.
 */
export function withinVerifiedDomains(
  entry: string,
  verifiedEmailDomains: readonly string[]
): boolean | null {
  const candidate = toALabel(entry);
  if (candidate === null) return null;

  for (const verified of verifiedEmailDomains) {
    const proven = toALabel(verified);
    if (proven === null) continue;
    if (candidate === proven || candidate.endsWith(`.${proven}`)) return true;
  }
  return false;
}

/**
 * Whether the API gave a verdict on domain ownership for the saved record.
 * A proven org always serves its proven set, and an unproven org lists every
 * saved entry as unverified; so saved entries with both arrays empty mean the
 * API could not derive the proof (the serializer's rescue path, or a GET
 * answered by an API that predates the fields during a rolling deploy) and no
 * verdict exists. With no saved entry the two states are not separable, and
 * the record counts as judged. The headline above the chips and the chips
 * themselves share this one definition.
 */
export function hasProofVerdict(context: AllowlistVerificationContext): boolean {
  return !(
    context.savedAllowedDomains.length > 0 &&
    context.verifiedEmailDomains.length === 0 &&
    context.unverifiedAllowedDomains.length === 0
  );
}

/**
 * Verified state of one allowlist entry. With no verdict on the record every
 * entry is `unknown`, saved or not: the empty proven set is then not a
 * judgment, and the save reports on it. Otherwise a saved entry takes the
 * API's verdict; an unsaved one is judged client-side against the proven set.
 */
export function allowlistEntryState(
  entry: string,
  context: AllowlistVerificationContext
): AllowlistEntryState {
  if (!hasProofVerdict(context)) return 'unknown';

  if (context.savedAllowedDomains.includes(entry)) {
    if (context.unverifiedAllowedDomains.includes(entry)) return 'unverified';
    // Listed in neither array while a proven set is served: inside it. With
    // no proven set either the record is inconsistent and no verdict exists.
    return context.verifiedEmailDomains.length > 0 ? 'verified' : 'unknown';
  }

  const within = withinVerifiedDomains(entry, context.verifiedEmailDomains);
  if (within === null) return 'unknown';
  return within ? 'verified' : 'unverified';
}
