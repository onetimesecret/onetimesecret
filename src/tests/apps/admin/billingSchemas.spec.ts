// src/tests/apps/admin/billingSchemas.spec.ts

import { describe, expect, it } from 'vitest';

import { colonelBillingCatalogResponseSchema } from '@/schemas/api/internal/responses/colonel-billing';

/**
 * Zod tripwire (CONTRACT 3) for the NEW Billing-catalog contract (ticket #45).
 * The payload is shaped exactly as the live logic class emits it — verified
 * against apps/api/colonel/logic/colonel/get_billing_catalog.rb, a read-only
 * adapter over Billing::Plan (list_plans + list_plans_from_config). If the
 * backend drifts, this fails rather than the screen silently breaking.
 */
describe('colonelBillingCatalogResponseSchema', () => {
  const validPlan = {
    planid: 'identity_plus_v1',
    name: 'Identity+',
    tier: 'single_team',
    tenancy: 'shared',
    region: 'US',
    display_order: 2,
    show_on_plans_page: true,
    description: null,
    entitlements: ['create_secrets', 'custom_domains'],
    limits: { 'teams.max': '1', 'custom_domains.max': 'unlimited' },
  };

  it('parses a full drift catalog (both sides + drift summary)', () => {
    const parsed = colonelBillingCatalogResponseSchema.parse({
      shrimp: '',
      record: {},
      details: {
        source: 'stripe',
        stripe_configured: true,
        config_plans: [validPlan],
        live_plans: [{ ...validPlan, entitlements: ['create_secrets'] }],
        drift: {
          in_sync: false,
          only_in_config: ['legacy_v1'],
          only_in_live: ['new_v2'],
          changed: [
            { planid: 'identity_plus_v1', name: 'Identity+', fields: ['entitlements'] },
          ],
        },
      },
    });
    expect(parsed.details?.source).toBe('stripe');
    expect(parsed.details?.drift.changed[0].fields).toContain('entitlements');
    expect(parsed.details?.config_plans[0].limits['teams.max']).toBe('1');
  });

  it('parses a local_config catalog with no live plans', () => {
    const parsed = colonelBillingCatalogResponseSchema.parse({
      shrimp: '',
      record: {},
      details: {
        source: 'local_config',
        stripe_configured: false,
        config_plans: [validPlan],
        live_plans: [],
        drift: { in_sync: false, only_in_config: ['identity_plus_v1'], only_in_live: [], changed: [] },
      },
    });
    expect(parsed.details?.stripe_configured).toBe(false);
    expect(parsed.details?.live_plans).toHaveLength(0);
  });

  it('rejects an unknown source enum value (contract drift)', () => {
    expect(() =>
      colonelBillingCatalogResponseSchema.parse({
        shrimp: '',
        record: {},
        details: {
          source: 'mysql', // not stripe | local_config
          stripe_configured: true,
          config_plans: [],
          live_plans: [],
          drift: { in_sync: true, only_in_config: [], only_in_live: [], changed: [] },
        },
      })
    ).toThrow();
  });

  it('rejects a non-string limit value (limits must be string→string)', () => {
    expect(() =>
      colonelBillingCatalogResponseSchema.parse({
        shrimp: '',
        record: {},
        details: {
          source: 'stripe',
          stripe_configured: true,
          config_plans: [{ ...validPlan, limits: { 'teams.max': 1 } }],
          live_plans: [],
          drift: { in_sync: true, only_in_config: [], only_in_live: [], changed: [] },
        },
      })
    ).toThrow();
  });
});
