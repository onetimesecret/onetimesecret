// src/tests/apps/admin/utils/verifyOutcomeNotice.spec.ts

import { verifyOutcomeNotice } from '@/apps/admin/utils/verifyOutcomeNotice';
import type { ColonelDomainVerifyDetails } from '@/schemas/api/internal/responses/colonel-domains';
import { describe, expect, it } from 'vitest';

function details(overrides: Partial<ColonelDomainVerifyDetails>): ColonelDomainVerifyDetails {
  return {
    previous_state: 'resolving',
    current_state: 'resolving',
    changed: false,
    dns_validated: false,
    ssl_ready: true,
    is_resolving: true,
    error: null,
    message: 'Domain verification completed',
    ...overrides,
  };
}

describe('verifyOutcomeNotice', () => {
  it('maps the post-verify state when the TXT outcome is ordinary', () => {
    expect(verifyOutcomeNotice(details({ current_state: 'verified', dns_outcome: 'validated' }))).toEqual({
      messageKey: 'web.admin.domains.verify.success.verified',
      severity: 'success',
    });
    expect(verifyOutcomeNotice(details({ dns_outcome: 'failed' }))).toEqual({
      messageKey: 'web.admin.domains.verify.success.resolving',
      severity: 'info',
    });
  });

  // A verified domain whose check came back indeterminate is still
  // `current_state: verified`; saying "is verified" would hide that the
  // checker produced no answer.
  it('prefers the indeterminate outcome over the state', () => {
    expect(
      verifyOutcomeNotice(details({ current_state: 'verified', dns_outcome: 'indeterminate' }))
    ).toEqual({
      messageKey: 'web.admin.domains.verify.success.indeterminate',
      severity: 'warning',
    });
  });

  it('reports a failed check held by an operator override', () => {
    expect(
      verifyOutcomeNotice(details({ current_state: 'verified', dns_outcome: 'override_held' }))
    ).toEqual({
      messageKey: 'web.admin.domains.verify.success.overrideHeld',
      severity: 'warning',
    });
  });

  // The state reads `resolving`, which would suggest the TXT record was
  // checked and did not match. It was never reached.
  it('reports a verification withdrawn after the confirmation window', () => {
    expect(
      verifyOutcomeNotice(
        details({
          previous_state: 'verified',
          current_state: 'resolving',
          changed: true,
          dns_outcome: 'confirmation_expired',
        })
      )
    ).toEqual({
      messageKey: 'web.admin.domains.verify.success.confirmationExpired',
      severity: 'warning',
    });
  });

  it('falls back to done for an unknown state, a response without dns_outcome, or null', () => {
    expect(verifyOutcomeNotice(details({ current_state: 'mystery' })).messageKey).toBe(
      'web.admin.domains.verify.success.done'
    );
    expect(verifyOutcomeNotice(null).messageKey).toBe('web.admin.domains.verify.success.done');
  });
});
