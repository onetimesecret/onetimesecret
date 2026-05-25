// src/tests/schemas/shapes/config/billing.spec.ts
//
// Smoke tests that the billing shape restores the value bounds previously
// enforced by the contract. These are the bounds the Ruby side does not
// independently validate, so the JSON Schema generated from the shape is
// the gate that `bin/ots billing catalog validate` relies on.

import { describe, it, expect } from 'vitest';
import { BillingConfigSchema } from '@/schemas/contracts/config/billing';
import {
  BillingConfigShape,
  LimitValueShape,
  PlanPriceShape,
  PlanDefinitionShape,
  EntitlementDefinitionShape,
} from '@/schemas/shapes/config/billing';

const validBillingConfig = {
  schema_version: '1.0',
  app_identifier: 'ots',
  entitlements: {
    base_feature: { category: 'core', description: 'Base feature' },
  },
  plans: {
    free_v1: {
      name: 'Free Plan',
      tier: 'free',
      entitlements: ['base_feature'],
      limits: {
        organizations: 1,
        members_per_team: 1,
        custom_domains: 0,
        secret_lifetime: 604800,
      },
      prices: [{ interval: 'month', amount: 0 }],
    },
  },
};

describe('BillingConfigShape — match_fields default', () => {
  it('applies the [\'plan_id\'] default when match_fields is omitted', () => {
    const result = BillingConfigShape.parse(validBillingConfig);
    expect(result.match_fields).toEqual(['plan_id']);
  });

  it('does not apply the default on the contract', () => {
    const result = BillingConfigSchema.parse(validBillingConfig);
    expect(result.match_fields).toBeUndefined();
  });
});

describe('LimitValueShape — lower bound', () => {
  it('accepts -1 (unlimited)', () => {
    expect(LimitValueShape.parse(-1)).toBe(-1);
  });

  it('accepts 0', () => {
    expect(LimitValueShape.parse(0)).toBe(0);
  });

  it('rejects values below -1', () => {
    expect(() => LimitValueShape.parse(-2)).toThrow();
  });

  it('accepts null (to be determined)', () => {
    expect(LimitValueShape.parse(null)).toBeNull();
  });
});

describe('PlanPriceShape — non-negative amount', () => {
  it('accepts zero amount (free plan)', () => {
    expect(PlanPriceShape.parse({ interval: 'month', amount: 0 })).toMatchObject({ amount: 0 });
  });

  it('rejects negative amount', () => {
    expect(() => PlanPriceShape.parse({ interval: 'month', amount: -500 })).toThrow();
  });
});

describe('PlanDefinitionShape — required non-empty strings', () => {
  it('rejects empty plan name', () => {
    expect(() =>
      PlanDefinitionShape.parse({
        name: '',
        entitlements: ['x'],
        limits: { organizations: 1, members_per_team: 1, custom_domains: 0, secret_lifetime: 1 },
        prices: [{ interval: 'month', amount: 0 }],
      })
    ).toThrow();
  });

  it('rejects negative display_order', () => {
    expect(() =>
      PlanDefinitionShape.parse({
        name: 'X',
        display_order: -5,
        entitlements: ['x'],
        limits: { organizations: 1, members_per_team: 1, custom_domains: 0, secret_lifetime: 1 },
        prices: [{ interval: 'month', amount: 0 }],
      })
    ).toThrow();
  });
});

describe('EntitlementDefinitionShape — non-empty description', () => {
  it('rejects empty description', () => {
    expect(() => EntitlementDefinitionShape.parse({ category: 'core', description: '' })).toThrow();
  });

  it('accepts a populated description', () => {
    const result = EntitlementDefinitionShape.parse({
      category: 'core',
      description: 'A feature',
    });
    expect(result.description).toBe('A feature');
  });
});
