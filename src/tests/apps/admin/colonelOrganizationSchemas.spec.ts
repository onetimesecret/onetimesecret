// src/tests/apps/admin/colonelOrganizationSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import {
  colonelOrganizationsResponseSchema,
  investigateOrganizationResponseSchema,
} from '@/schemas/api/internal/responses/colonel';
import { colonelEntitlementOverrideResponseSchema } from '@/schemas/api/internal/responses/colonel-organizations';

/**
 * Zod tripwire (CONTRACT 3, ticket #32). The organizations screen REUSES the
 * frozen list + investigate schemas and adds ONE new schema for the
 * entitlement-override MUTATION endpoints. These payloads are shaped exactly as
 * the colonel logic classes emit them (verified against list_organizations.rb /
 * investigate_organization.rb / manage_entitlement_override.rb). If the backend
 * response drifts, these fail rather than the UI silently breaking.
 */

describe('colonelOrganizationsResponseSchema (reused list contract)', () => {
  it('parses the real list payload and transforms created/updated to Date', () => {
    const payload = {
      shrimp: '',
      record: {},
      details: {
        organizations: [
          {
            org_id: 'org1',
            extid: 'on_abc',
            display_name: 'Acme',
            contact_email: 'owner@acme.test',
            owner_id: 'cust1',
            owner_email: 'ow***@a***.test',
            member_count: 2,
            domain_count: 0,
            is_default: false,
            created: 1700000000.5,
            updated: null,
            planid: null,
            stripe_customer_id: null,
            stripe_subscription_id: null,
            subscription_status: null,
            subscription_period_end: null,
            billing_email: null,
            sync_status: 'unknown',
            sync_status_reason: null,
          },
        ],
        pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1 },
        filters: { status: null, sync_status: null },
      },
    };
    const result = colonelOrganizationsResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.details?.organizations[0].created).toBeInstanceOf(Date);
    expect(result.data.details?.organizations[0].updated).toBeNull();
  });

  it('rejects an unknown sync_status (contract drift)', () => {
    const payload = {
      shrimp: '',
      record: {},
      details: {
        organizations: [
          {
            org_id: 'o',
            extid: 'on_x',
            display_name: null,
            contact_email: null,
            owner_id: null,
            owner_email: null,
            member_count: 0,
            domain_count: 0,
            is_default: true,
            created: 1700000000,
            updated: null,
            planid: null,
            stripe_customer_id: null,
            stripe_subscription_id: null,
            subscription_status: null,
            subscription_period_end: null,
            billing_email: null,
            sync_status: 'exploded',
            sync_status_reason: null,
          },
        ],
        pagination: { page: 1, per_page: 50, total_count: 1, total_pages: 1 },
        filters: { status: null, sync_status: null },
      },
    };
    expect(colonelOrganizationsResponseSchema.safeParse(payload).success).toBe(false);
  });
});

describe('investigateOrganizationResponseSchema (reused investigate contract)', () => {
  it('parses a mismatch verdict with issues + stripe subscription', () => {
    const payload = {
      shrimp: '',
      record: {
        org_id: 'org1',
        extid: 'on_abc',
        investigated_at: '2026-07-06 12:00:00 UTC',
        local: {
          planid: 'free_v1',
          stripe_customer_id: 'cus_1',
          stripe_subscription_id: 'sub_1',
          subscription_status: 'active',
          subscription_period_end: null,
        },
        stripe: {
          available: true,
          reason: null,
          subscription: {
            id: 'sub_1',
            status: 'active',
            current_period_end: 1735689600,
            price_id: 'price_1',
            price_nickname: null,
            product_id: 'prod_1',
            product_name: 'Identity Plus',
            subscription_metadata_plan_id: null,
            price_metadata_plan_id: 'identity_plus_v1',
            resolved_plan_id: 'identity_plus_v1',
          },
        },
        comparison: {
          match: false,
          verdict: 'mismatch_detected',
          details: 'planid differs',
          issues: [
            { field: 'planid', local: 'free_v1', stripe: 'identity_plus_v1', severity: 'high' },
          ],
        },
      },
    };
    const result = investigateOrganizationResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.comparison.verdict).toBe('mismatch_detected');
    expect(result.data.record.comparison.issues?.[0].severity).toBe('high');
  });

  it('parses a "no subscription" investigation (stripe unavailable)', () => {
    const payload = {
      shrimp: '',
      record: {
        org_id: 'org1',
        extid: 'on_abc',
        investigated_at: '2026-07-06 12:00:00 UTC',
        local: {
          planid: null,
          stripe_customer_id: null,
          stripe_subscription_id: null,
          subscription_status: null,
          subscription_period_end: null,
        },
        stripe: { available: false, reason: 'No subscription ID stored locally', subscription: null },
        comparison: { match: null, verdict: 'unable_to_compare' },
      },
    };
    expect(investigateOrganizationResponseSchema.safeParse(payload).success).toBe(true);
  });
});

describe('colonelEntitlementOverrideResponseSchema (new mutation ack)', () => {
  it('validates a grant ack', () => {
    const payload = {
      shrimp: '',
      record: {
        org_id: 'org1',
        extid: 'on_abc',
        entitlement: 'custom_domains',
        action: 'granted',
        effective_entitlements: ['create_secrets', 'custom_domains'],
        grants: ['custom_domains'],
        revokes: [],
      },
    };
    const result = colonelEntitlementOverrideResponseSchema.safeParse(payload);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.record.action).toBe('granted');
    expect(result.data.record.grants).toContain('custom_domains');
  });

  it('validates a clear ack (null entitlement, empty overrides)', () => {
    const payload = {
      shrimp: '',
      record: {
        org_id: 'org1',
        extid: 'on_abc',
        entitlement: null,
        action: 'cleared',
        effective_entitlements: ['create_secrets'],
        grants: [],
        revokes: [],
      },
    };
    expect(colonelEntitlementOverrideResponseSchema.safeParse(payload).success).toBe(true);
  });

  it('rejects an unknown action (contract drift)', () => {
    const payload = {
      shrimp: '',
      record: {
        org_id: 'org1',
        extid: 'on_abc',
        entitlement: 'x',
        action: 'exploded',
        effective_entitlements: [],
        grants: [],
        revokes: [],
      },
    };
    expect(colonelEntitlementOverrideResponseSchema.safeParse(payload).success).toBe(false);
  });
});
