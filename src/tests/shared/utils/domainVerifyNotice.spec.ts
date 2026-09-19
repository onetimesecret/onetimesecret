// src/tests/shared/utils/domainVerifyNotice.spec.ts

import { customDomainDetailsSchema as domainsApiDetailsSchema } from '@/schemas/api/domains/responses/domains';
import { customDomainDetailsSchema } from '@/schemas/api/v3/responses/domains';
import { domainVerifyNotice } from '@/shared/utils/domainVerifyNotice';
import { describe, expect, it } from 'vitest';

const COMPLETED = {
  messageKey: 'web.domains.domain_verification_initiated_successfully',
  severity: 'success',
};
const INCOMPLETE = { messageKey: 'web.domains.verify_outcome.indeterminate', severity: 'warning' };
const RECORD_NOT_FOUND = {
  messageKey: 'web.domains.verify_outcome.record_not_found',
  severity: 'info',
};

describe('domainVerifyNotice', () => {
  it('keeps the success text for a matching TXT record only', () => {
    expect(domainVerifyNotice({ dns_outcome: 'validated', dns_indeterminate: false })).toEqual(
      COMPLETED
    );
  });

  it.each(['indeterminate', 'confirmation_expired'])(
    '%s reads as "could not complete the check", not as a missing record',
    (dns_outcome) => {
      const notice = domainVerifyNotice({ dns_outcome, dns_indeterminate: true });

      expect(notice).toEqual(INCOMPLETE);
      expect(notice).not.toEqual(RECORD_NOT_FOUND);
    }
  );

  it.each(['failed', 'override_held'])('%s reads as "record not found"', (dns_outcome) => {
    expect(domainVerifyNotice({ dns_outcome, dns_indeterminate: false })).toEqual(
      RECORD_NOT_FOUND
    );
  });

  it('an outcome this client does not know still honours dns_indeterminate', () => {
    expect(domainVerifyNotice({ dns_outcome: 'something_new', dns_indeterminate: true })).toEqual(
      INCOMPLETE
    );
  });

  it.each([null, undefined, {}])('falls back to the neutral text without an outcome (%s)', (d) => {
    expect(domainVerifyNotice(d)).toEqual(COMPLETED);
  });
});

// The verify response is parsed with these schemas before it reaches the
// notice; a stripped field would silently turn every outcome into the fallback.
describe.each([
  ['v3', customDomainDetailsSchema],
  ['domains API', domainsApiDetailsSchema],
])('customDomainDetailsSchema (%s)', (_label, schema) => {
  it('keeps the TXT outcome fields', () => {
    const parsed = schema.parse({
      cluster: { type: 'caddy_on_demand', validation_strategy: 'caddy_on_demand' },
      dns_outcome: 'indeterminate',
      dns_indeterminate: true,
    });

    expect(parsed.dns_outcome).toBe('indeterminate');
    expect(parsed.dns_indeterminate).toBe(true);
  });

  it('accepts a response without them (GET and list responses)', () => {
    const parsed = schema.parse({ cluster: null });

    expect(parsed.dns_outcome).toBeUndefined();
    expect(parsed.dns_indeterminate).toBeUndefined();
  });

  it('does not reject an outcome added server-side', () => {
    expect(schema.safeParse({ dns_outcome: 'something_new' }).success).toBe(true);
  });
});
