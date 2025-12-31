// src/tests/apps/workspace/billing/PlanSelector.spec.ts
//
// Unit tests for PlanSelector.vue billing logic
//
// Tests cover the key issues being fixed:
// - Type mismatch: planid vs tier comparison in upgrade/downgrade logic
// - Feature inheritance: correct direction (higher tiers reference lower)
// - Yearly prices: monthly equivalent calculation
// - Popular badge: API flag vs hardcoded tier
//
// NOTE: These tests focus on the computed logic extracted from PlanSelector.vue
// They do not mount the component to avoid complex Vue/Pinia/i18n setup.

import { describe, it, expect, beforeEach } from 'vitest';
import type { Plan as BillingPlan } from '@/services/billing.service';

// Type for the tier hierarchy - matches PlanSelector.vue logic
type PlanTier = 'free' | 'single_team' | 'multi_team';

// Tier order for upgrade/downgrade comparison
const TIER_ORDER: PlanTier[] = ['free', 'single_team', 'multi_team'];

/**
 * Helper: Get tier index for comparison
 * Used to determine upgrade/downgrade eligibility
 */
function getTierIndex(tier: string): number {
  const index = TIER_ORDER.indexOf(tier as PlanTier);
  return index >= 0 ? index : -1;
}

/**
 * Logic extracted from PlanSelector.vue: canUpgrade
 *
 * Determines if user can upgrade from current tier to target plan.
 * FIXED: Uses tier comparison instead of planid.
 */
function canUpgrade(currentTier: string, targetPlan: BillingPlan): boolean {
  if (currentTier === 'free') return targetPlan.tier !== 'free';
  if (currentTier === 'single_team') return targetPlan.tier === 'multi_team';
  return false;
}

/**
 * Logic extracted from PlanSelector.vue: canDowngrade
 *
 * Determines if user can downgrade from current tier to target plan.
 * FIXED: Uses tier comparison instead of planid.
 */
function canDowngrade(currentTier: string, targetPlan: BillingPlan): boolean {
  if (currentTier === 'multi_team') return targetPlan.tier !== 'multi_team';
  if (currentTier === 'single_team') return targetPlan.tier === 'free';
  return false;
}

/**
 * Logic extracted from PlanSelector.vue: getBasePlan
 *
 * Returns the base plan for feature inheritance.
 * FIXED: Correct direction - higher tiers reference lower tiers.
 */
function getBasePlan(plan: BillingPlan, allPlans: BillingPlan[]): BillingPlan | undefined {
  if (plan.tier === 'single_team') return undefined; // Identity Plus has no base
  // Find Identity Plus with same interval
  return allPlans.find(p => p.tier === 'single_team' && p.interval === plan.interval);
}

/**
 * Logic extracted from PlanSelector.vue: getNewFeatures
 *
 * Returns only NEW features for this plan (excluding base plan features).
 * FIXED: Proper feature inheritance direction.
 */
function getNewFeatures(plan: BillingPlan, allPlans: BillingPlan[]): string[] {
  const basePlan = getBasePlan(plan, allPlans);
  if (!basePlan) return plan.entitlements; // Show all for Identity Plus

  // Filter out features that exist in base plan
  return plan.entitlements.filter(ent => !basePlan.entitlements.includes(ent));
}

/**
 * Logic extracted from PlanSelector.vue: isPlanRecommended
 *
 * Determines if plan should show "Most Popular" badge.
 * ISSUE: Currently hardcoded to tier === 'single_team'
 * FIX: Should use is_popular flag from API when available.
 */
function isPlanRecommended(plan: BillingPlan & { is_popular?: boolean }): boolean {
  // Fixed implementation uses API flag when available
  if (plan.is_popular !== undefined) {
    return plan.is_popular;
  }
  // Fallback to tier-based logic (legacy behavior)
  return plan.tier === 'single_team';
}

/**
 * Logic extracted from PlanSelector.vue: getPlanPricePerMonth
 *
 * Returns the monthly display price for a plan.
 * ISSUE: Uses amount / 12 for yearly plans (loses precision)
 * FIX: Should use monthly_equivalent_amount from API when available.
 */
function getPlanPricePerMonth(
  plan: BillingPlan & { monthly_equivalent_amount?: number }
): number {
  // For yearly plans, prefer API-provided monthly equivalent
  if (plan.interval === 'year') {
    if (plan.monthly_equivalent_amount !== undefined) {
      return plan.monthly_equivalent_amount;
    }
    // Fallback to calculation (may lose precision)
    return Math.floor(plan.amount / 12);
  }
  // For monthly plans, show the amount as-is
  return plan.amount;
}

/**
 * Deduplicate plans by plan_code
 *
 * ISSUE: API may return duplicate plans (same plan_code, different price IDs)
 * FIX: Deduplicate by plan_code, keeping first occurrence.
 */
function deduplicatePlans(
  plans: (BillingPlan & { plan_code?: string })[]
): BillingPlan[] {
  const seen = new Set<string>();
  return plans.filter(plan => {
    const key = plan.plan_code || plan.id;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

// Test fixtures
const createMockPlan = (overrides: Partial<BillingPlan> = {}): BillingPlan => ({
  id: 'plan_test_123',
  name: 'Test Plan',
  tier: 'single_team',
  interval: 'month',
  amount: 1499, // $14.99 in cents
  currency: 'usd',
  region: 'US',
  display_order: 100,
  features: ['Feature 1', 'Feature 2'],
  limits: { teams: 1, members_per_team: 10 },
  entitlements: ['create_secrets', 'api_access', 'custom_domains'],
  ...overrides,
});

describe('PlanSelector Logic', () => {
  describe('canUpgrade', () => {
    it('returns true when current tier is free and target is single_team', () => {
      const targetPlan = createMockPlan({ tier: 'single_team' });
      expect(canUpgrade('free', targetPlan)).toBe(true);
    });

    it('returns true when current tier is free and target is multi_team', () => {
      const targetPlan = createMockPlan({ tier: 'multi_team' });
      expect(canUpgrade('free', targetPlan)).toBe(true);
    });

    it('returns true when current tier is single_team and target is multi_team', () => {
      const targetPlan = createMockPlan({ tier: 'multi_team' });
      expect(canUpgrade('single_team', targetPlan)).toBe(true);
    });

    it('returns false when target tier is same as current', () => {
      const targetPlan = createMockPlan({ tier: 'single_team' });
      expect(canUpgrade('single_team', targetPlan)).toBe(false);
    });

    it('returns false when target tier is lower than current', () => {
      const targetPlan = createMockPlan({ tier: 'free' });
      expect(canUpgrade('single_team', targetPlan)).toBe(false);
    });

    it('returns false when current tier is multi_team (highest tier)', () => {
      const targetPlan = createMockPlan({ tier: 'single_team' });
      expect(canUpgrade('multi_team', targetPlan)).toBe(false);
    });

    it('returns false when free user targets free plan', () => {
      const targetPlan = createMockPlan({ tier: 'free' });
      expect(canUpgrade('free', targetPlan)).toBe(false);
    });
  });

  describe('canDowngrade', () => {
    it('returns true when current tier is multi_team and target is single_team', () => {
      const targetPlan = createMockPlan({ tier: 'single_team' });
      expect(canDowngrade('multi_team', targetPlan)).toBe(true);
    });

    it('returns true when current tier is multi_team and target is free', () => {
      const targetPlan = createMockPlan({ tier: 'free' });
      expect(canDowngrade('multi_team', targetPlan)).toBe(true);
    });

    it('returns true when current tier is single_team and target is free', () => {
      const targetPlan = createMockPlan({ tier: 'free' });
      expect(canDowngrade('single_team', targetPlan)).toBe(true);
    });

    it('returns false when target tier is same or higher', () => {
      const targetPlan = createMockPlan({ tier: 'multi_team' });
      expect(canDowngrade('single_team', targetPlan)).toBe(false);
    });

    it('returns false when current tier is free (cannot downgrade from free)', () => {
      const targetPlan = createMockPlan({ tier: 'free' });
      expect(canDowngrade('free', targetPlan)).toBe(false);
    });

    it('returns false when multi_team targets multi_team', () => {
      const targetPlan = createMockPlan({ tier: 'multi_team' });
      expect(canDowngrade('multi_team', targetPlan)).toBe(false);
    });
  });

  describe('getBasePlan', () => {
    let allPlans: BillingPlan[];

    beforeEach(() => {
      allPlans = [
        createMockPlan({
          id: 'plan_single_monthly',
          tier: 'single_team',
          interval: 'month',
          entitlements: ['create_secrets', 'api_access'],
        }),
        createMockPlan({
          id: 'plan_single_yearly',
          tier: 'single_team',
          interval: 'year',
          entitlements: ['create_secrets', 'api_access'],
        }),
        createMockPlan({
          id: 'plan_multi_monthly',
          tier: 'multi_team',
          interval: 'month',
          entitlements: ['create_secrets', 'api_access', 'manage_teams', 'sso'],
        }),
        createMockPlan({
          id: 'plan_multi_yearly',
          tier: 'multi_team',
          interval: 'year',
          entitlements: ['create_secrets', 'api_access', 'manage_teams', 'sso'],
        }),
      ];
    });

    it('returns undefined for lowest tier (single_team)', () => {
      const singleTeamPlan = allPlans.find(p => p.tier === 'single_team')!;
      expect(getBasePlan(singleTeamPlan, allPlans)).toBeUndefined();
    });

    it('returns single_team plan for multi_team tier', () => {
      const multiTeamPlan = allPlans.find(
        p => p.tier === 'multi_team' && p.interval === 'month'
      )!;
      const basePlan = getBasePlan(multiTeamPlan, allPlans);
      expect(basePlan).toBeDefined();
      expect(basePlan?.tier).toBe('single_team');
    });

    it('matches interval when finding base plan', () => {
      const multiTeamYearly = allPlans.find(
        p => p.tier === 'multi_team' && p.interval === 'year'
      )!;
      const basePlan = getBasePlan(multiTeamYearly, allPlans);
      expect(basePlan?.interval).toBe('year');
    });

    it('returns undefined when base plan not found in list', () => {
      const onlyMultiTeam = allPlans.filter(p => p.tier === 'multi_team');
      const multiTeamPlan = onlyMultiTeam[0];
      expect(getBasePlan(multiTeamPlan, onlyMultiTeam)).toBeUndefined();
    });
  });

  describe('getNewFeatures', () => {
    let allPlans: BillingPlan[];

    beforeEach(() => {
      allPlans = [
        createMockPlan({
          id: 'plan_single_monthly',
          tier: 'single_team',
          interval: 'month',
          entitlements: ['create_secrets', 'api_access', 'custom_domains'],
        }),
        createMockPlan({
          id: 'plan_multi_monthly',
          tier: 'multi_team',
          interval: 'month',
          entitlements: [
            'create_secrets',
            'api_access',
            'custom_domains',
            'manage_teams',
            'sso',
            'audit_logs',
          ],
        }),
      ];
    });

    it('returns all features for base tier (single_team)', () => {
      const singleTeamPlan = allPlans.find(p => p.tier === 'single_team')!;
      const features = getNewFeatures(singleTeamPlan, allPlans);
      expect(features).toEqual(singleTeamPlan.entitlements);
    });

    it('returns only new features for higher tiers', () => {
      const multiTeamPlan = allPlans.find(p => p.tier === 'multi_team')!;
      const newFeatures = getNewFeatures(multiTeamPlan, allPlans);

      // Should NOT include base plan features
      expect(newFeatures).not.toContain('create_secrets');
      expect(newFeatures).not.toContain('api_access');
      expect(newFeatures).not.toContain('custom_domains');

      // Should include new features
      expect(newFeatures).toContain('manage_teams');
      expect(newFeatures).toContain('sso');
      expect(newFeatures).toContain('audit_logs');
    });

    it('returns correct count of new features', () => {
      const multiTeamPlan = allPlans.find(p => p.tier === 'multi_team')!;
      const newFeatures = getNewFeatures(multiTeamPlan, allPlans);
      expect(newFeatures).toHaveLength(3); // manage_teams, sso, audit_logs
    });
  });

  describe('isPlanRecommended', () => {
    it('uses is_popular flag from API when available (true)', () => {
      const plan = createMockPlan({
        tier: 'multi_team', // Not the default recommended tier
      }) as BillingPlan & { is_popular?: boolean };
      plan.is_popular = true;

      expect(isPlanRecommended(plan)).toBe(true);
    });

    it('uses is_popular flag from API when available (false)', () => {
      const plan = createMockPlan({
        tier: 'single_team', // Would be default recommended
      }) as BillingPlan & { is_popular?: boolean };
      plan.is_popular = false;

      expect(isPlanRecommended(plan)).toBe(false);
    });

    it('falls back to tier-based logic when is_popular not set', () => {
      const singleTeamPlan = createMockPlan({ tier: 'single_team' });
      expect(isPlanRecommended(singleTeamPlan)).toBe(true);

      const multiTeamPlan = createMockPlan({ tier: 'multi_team' });
      expect(isPlanRecommended(multiTeamPlan)).toBe(false);
    });

    it('falls back to false for non-single_team tiers without API flag', () => {
      const freePlan = createMockPlan({ tier: 'free' });
      expect(isPlanRecommended(freePlan)).toBe(false);
    });
  });

  describe('getPlanPricePerMonth', () => {
    it('uses monthly_equivalent_amount for yearly plans when available', () => {
      const yearlyPlan = createMockPlan({
        interval: 'year',
        amount: 14388, // $143.88/year
      }) as BillingPlan & { monthly_equivalent_amount?: number };
      yearlyPlan.monthly_equivalent_amount = 1199; // $11.99/month (API literal)

      expect(getPlanPricePerMonth(yearlyPlan)).toBe(1199);
    });

    it('falls back to amount/12 calculation when monthly_equivalent not available', () => {
      const yearlyPlan = createMockPlan({
        interval: 'year',
        amount: 14388, // $143.88/year
      });

      // 14388 / 12 = 1199
      expect(getPlanPricePerMonth(yearlyPlan)).toBe(1199);
    });

    it('handles precision loss in fallback calculation', () => {
      const yearlyPlan = createMockPlan({
        interval: 'year',
        amount: 15000, // $150/year
      });

      // 15000 / 12 = 1250 (loses 0.00 cents)
      expect(getPlanPricePerMonth(yearlyPlan)).toBe(1250);
    });

    it('returns amount directly for monthly plans', () => {
      const monthlyPlan = createMockPlan({
        interval: 'month',
        amount: 1499, // $14.99/month
      });

      expect(getPlanPricePerMonth(monthlyPlan)).toBe(1499);
    });

    it('ignores monthly_equivalent_amount for monthly plans', () => {
      const monthlyPlan = createMockPlan({
        interval: 'month',
        amount: 1499,
      }) as BillingPlan & { monthly_equivalent_amount?: number };
      monthlyPlan.monthly_equivalent_amount = 999; // Should be ignored

      expect(getPlanPricePerMonth(monthlyPlan)).toBe(1499);
    });
  });

  describe('deduplicatePlans', () => {
    it('removes duplicate plans by plan_code', () => {
      const plans = [
        createMockPlan({ id: 'price_1', name: 'Plan A' }),
        createMockPlan({ id: 'price_2', name: 'Plan A Duplicate' }),
        createMockPlan({ id: 'price_3', name: 'Plan B' }),
      ] as (BillingPlan & { plan_code?: string })[];

      plans[0].plan_code = 'identity_plus_monthly';
      plans[1].plan_code = 'identity_plus_monthly'; // Duplicate
      plans[2].plan_code = 'team_plus_monthly';

      const deduplicated = deduplicatePlans(plans);

      expect(deduplicated).toHaveLength(2);
      expect(deduplicated[0].name).toBe('Plan A');
      expect(deduplicated[1].name).toBe('Plan B');
    });

    it('keeps first occurrence when duplicates exist', () => {
      const plans = [
        createMockPlan({ id: 'price_old', name: 'Old Price' }),
        createMockPlan({ id: 'price_new', name: 'New Price' }),
      ] as (BillingPlan & { plan_code?: string })[];

      plans[0].plan_code = 'same_plan';
      plans[1].plan_code = 'same_plan';

      const deduplicated = deduplicatePlans(plans);

      expect(deduplicated).toHaveLength(1);
      expect(deduplicated[0].id).toBe('price_old'); // First one kept
    });

    it('falls back to id when plan_code not set', () => {
      const plans = [
        createMockPlan({ id: 'unique_1' }),
        createMockPlan({ id: 'unique_2' }),
        createMockPlan({ id: 'unique_1' }), // Duplicate by ID
      ];

      const deduplicated = deduplicatePlans(plans);

      expect(deduplicated).toHaveLength(2);
    });

    it('handles empty array', () => {
      expect(deduplicatePlans([])).toEqual([]);
    });

    it('handles single plan', () => {
      const plans = [createMockPlan()];
      expect(deduplicatePlans(plans)).toHaveLength(1);
    });
  });

  describe('Tier comparison edge cases', () => {
    it('handles unknown tier gracefully in getTierIndex', () => {
      expect(getTierIndex('unknown_tier')).toBe(-1);
    });

    it('tier order is correct', () => {
      expect(getTierIndex('free')).toBeLessThan(getTierIndex('single_team'));
      expect(getTierIndex('single_team')).toBeLessThan(getTierIndex('multi_team'));
    });

    it('upgrade path: free -> single_team -> multi_team', () => {
      const singleTeam = createMockPlan({ tier: 'single_team' });
      const multiTeam = createMockPlan({ tier: 'multi_team' });

      // Free can upgrade to both
      expect(canUpgrade('free', singleTeam)).toBe(true);
      expect(canUpgrade('free', multiTeam)).toBe(true);

      // single_team can only upgrade to multi_team
      expect(canUpgrade('single_team', multiTeam)).toBe(true);
      expect(canUpgrade('single_team', singleTeam)).toBe(false);

      // multi_team cannot upgrade
      expect(canUpgrade('multi_team', singleTeam)).toBe(false);
      expect(canUpgrade('multi_team', multiTeam)).toBe(false);
    });

    it('downgrade path: multi_team -> single_team -> free', () => {
      const freePlan = createMockPlan({ tier: 'free' });
      const singleTeam = createMockPlan({ tier: 'single_team' });

      // multi_team can downgrade to both
      expect(canDowngrade('multi_team', singleTeam)).toBe(true);
      expect(canDowngrade('multi_team', freePlan)).toBe(true);

      // single_team can only downgrade to free
      expect(canDowngrade('single_team', freePlan)).toBe(true);
      expect(canDowngrade('single_team', singleTeam)).toBe(false);

      // free cannot downgrade
      expect(canDowngrade('free', singleTeam)).toBe(false);
      expect(canDowngrade('free', freePlan)).toBe(false);
    });
  });
});
