// src/apps/admin/utils/verifyOutcomeNotice.ts

import type { ColonelDomainVerifyDetails } from '@/schemas/api/internal/responses/colonel-domains';

/**
 * The operator notification for a colonel domain verify, chosen once here
 * instead of at each of the three call sites (domains list, org panel, domain
 * detail).
 *
 * `current_state` alone misleads for two TXT outcomes that leave `verified`
 * untouched, so `dns_outcome` wins when it names one of them:
 *
 *   - `indeterminate`  the upstream DNS checker produced no answer
 *   - `override_held`  the TXT check failed but an operator override holds
 *
 * Everything else maps from the post-verify state; unknown states fall back to
 * `done`.
 */
const STATE_MESSAGE_KEYS: Record<string, string> = {
  verified: 'web.admin.domains.verify.success.verified',
  resolving: 'web.admin.domains.verify.success.resolving',
  pending: 'web.admin.domains.verify.success.pending',
  unverified: 'web.admin.domains.verify.success.unverified',
};

const OUTCOME_MESSAGE_KEYS: Record<string, string> = {
  indeterminate: 'web.admin.domains.verify.success.indeterminate',
  override_held: 'web.admin.domains.verify.success.overrideHeld',
};

export interface VerifyOutcomeNotice {
  messageKey: string;
  severity: 'success' | 'info' | 'warning';
}

export function verifyOutcomeNotice(
  details: ColonelDomainVerifyDetails | null | undefined
): VerifyOutcomeNotice {
  const outcomeKey = OUTCOME_MESSAGE_KEYS[details?.dns_outcome ?? ''];
  if (outcomeKey) return { messageKey: outcomeKey, severity: 'warning' };

  const state = details?.current_state ?? '';
  return {
    messageKey: STATE_MESSAGE_KEYS[state] ?? 'web.admin.domains.verify.success.done',
    severity: state === 'verified' ? 'success' : 'info',
  };
}
