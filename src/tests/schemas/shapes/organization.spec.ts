// src/tests/schemas/shapes/organization.spec.ts
//
// Shape tests for organizationSchema's delete-guardrail fields.
//
// active_subscription mirrors the server's `:active_subscription` refusal in
// Onetime::Operations::Org::Delete (see the org safe_dump field of the same
// name). The workspace UI pre-disables its delete button on it, so the
// normalization matters: an absent field must NOT read as "blocked", or an
// older/partial payload would lock an owner out of a delete the server would
// have allowed.

import { organizationSchema } from '@/schemas/shapes/organizations/organization';
import { describe, expect, it } from 'vitest';
import { createCanonicalOrganization } from './fixtures/organization.fixtures';

// The shared fixture predates the canonical plan-id format, so pin a valid
// planid here rather than fail on an unrelated field.
const baseOrg = () => ({ ...createCanonicalOrganization(), planid: 'free_v1' });

const parse = (overrides: Record<string, unknown> = {}) =>
  organizationSchema.parse({ ...baseOrg(), ...overrides });

describe('organizationSchema — active_subscription', () => {
  it('keeps a true flag (org is actively billing)', () => {
    expect(parse({ active_subscription: true }).active_subscription).toBe(true);
  });

  it('keeps a false flag', () => {
    expect(parse({ active_subscription: false }).active_subscription).toBe(false);
  });

  it('normalizes an absent field to false, not blocked', () => {
    expect(parse().active_subscription).toBe(false);
  });

  it('normalizes null to false', () => {
    expect(parse({ active_subscription: null }).active_subscription).toBe(false);
  });

  it('rejects a non-boolean rather than coercing it', () => {
    const result = organizationSchema.safeParse({
      ...baseOrg(),
      active_subscription: 'active',
    });
    expect(result.success).toBe(false);
  });
});
