// src/shared/utils/domainVerifyNotice.ts

import type { CustomDomainDetails } from '@/schemas/api/v3/responses/domains';

/**
 * The customer-facing message for a domain verify, chosen once here for the
 * toast (useDomainsManager) and the inline alert (VerifyDomainDetails).
 *
 * The refreshed record cannot tell these apart: a TXT check that produced no
 * answer leaves `verified` as it was, so the badge reads the same as it does
 * after a definitive "no". `details.dns_outcome` carries the difference:
 *
 *   - `validated`             the TXT record matches
 *   - `indeterminate`         the lookup produced no answer; nothing was learned
 *   - `confirmation_expired`  no answer for longer than the confirmation window
 *   - `failed`                the record is missing or has a different value
 *   - `override_held`         as `failed`, but an operator override keeps the
 *                             domain verified
 *
 * "Could not tell" asks the customer to try again, not to change DNS that may
 * be correct. An absent or unrecognised outcome (an older server) keeps the
 * neutral text the verify action has always shown.
 *
 * The Colonel counterpart is `@/apps/admin/utils/verifyOutcomeNotice`.
 */
export type DomainVerifyNoticeSeverity = 'success' | 'info' | 'warning';

export interface DomainVerifyNotice {
  messageKey: string;
  severity: DomainVerifyNoticeSeverity;
}

const COMPLETED: DomainVerifyNotice = {
  messageKey: 'web.domains.domain_verification_initiated_successfully',
  severity: 'success',
};

const INCOMPLETE: DomainVerifyNotice = {
  messageKey: 'web.domains.verify_outcome.indeterminate',
  severity: 'warning',
};

const RECORD_NOT_FOUND: DomainVerifyNotice = {
  messageKey: 'web.domains.verify_outcome.record_not_found',
  severity: 'info',
};

const OUTCOME_NOTICES: Record<string, DomainVerifyNotice> = {
  validated: COMPLETED,
  indeterminate: INCOMPLETE,
  confirmation_expired: INCOMPLETE,
  failed: RECORD_NOT_FOUND,
  override_held: RECORD_NOT_FOUND,
};

export function domainVerifyNotice(
  details: Pick<CustomDomainDetails, 'dns_outcome' | 'dns_indeterminate'> | null | undefined
): DomainVerifyNotice {
  const notice = OUTCOME_NOTICES[details?.dns_outcome ?? ''];
  if (notice) return notice;

  // An outcome this client does not know, flagged as "could not tell".
  return details?.dns_indeterminate === true ? INCOMPLETE : COMPLETED;
}
