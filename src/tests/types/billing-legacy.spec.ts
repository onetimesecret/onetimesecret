// src/tests/types/billing-legacy.spec.ts

/**
 * Unit tests for legacy plan detection and display in billing utilities
 *
 * These tests cover the new legacy plan handling functionality:
 * - isLegacyPlan() - detects grandfathered plans
 * - getLegacyPlanInfo() - returns legacy plan metadata
 * - getPlanDisplayName() - displays legacy plans with special suffix
 *
 * Legacy plans are grandfathered plans no longer available for new subscriptions
 * but honored for existing customers (e.g., 'identity' -> 'Identity Plus (Early Supporter)')
 */

import { describe, it, expect } from 'vitest';
import {
  isLegacyPlan,
  getLegacyPlanInfo,
  getPlanDisplayName,
} from '@/types/billing';

describe('Legacy Plan Utilities', () => {
  // ============================================================
  // isLegacyPlan() Tests
  // ============================================================
  describe('isLegacyPlan()', () => {
    describe('returns true for legacy plans', () => {
      it('returns true for "identity" (exact match)', () => {
        expect(isLegacyPlan('identity')).toBe(true);
      });
    });

    describe('returns false for current plans', () => {
      it('returns false for "identity_plus_v1_monthly"', () => {
        expect(isLegacyPlan('identity_plus_v1_monthly')).toBe(false);
      });

      it('returns false for "identity_plus_v1_yearly"', () => {
        expect(isLegacyPlan('identity_plus_v1_yearly')).toBe(false);
      });

      it('returns false for "free_v1"', () => {
        expect(isLegacyPlan('free_v1')).toBe(false);
      });

      it('returns false for "team_plus_v1_monthly"', () => {
        expect(isLegacyPlan('team_plus_v1_monthly')).toBe(false);
      });

      it('returns false for "single_team_v1_monthly"', () => {
        expect(isLegacyPlan('single_team_v1_monthly')).toBe(false);
      });
    });

    describe('handles edge cases', () => {
      it('returns false for empty string', () => {
        expect(isLegacyPlan('')).toBe(false);
      });

      it('returns false for null (coerced to string)', () => {
        // TypeScript would prevent this, but runtime might pass null
        expect(isLegacyPlan(null as unknown as string)).toBe(false);
      });

      it('returns false for undefined (coerced to string)', () => {
        expect(isLegacyPlan(undefined as unknown as string)).toBe(false);
      });

      it('returns false for similar-but-not-exact matches', () => {
        // These contain "identity" but are not the exact legacy plan ID
        expect(isLegacyPlan('identity_')).toBe(false);
        expect(isLegacyPlan('_identity')).toBe(false);
        expect(isLegacyPlan('IDENTITY')).toBe(false); // Case sensitive
        expect(isLegacyPlan('Identity')).toBe(false);
      });

      it('returns false for arbitrary strings', () => {
        expect(isLegacyPlan('some_random_plan')).toBe(false);
        expect(isLegacyPlan('enterprise')).toBe(false);
      });
    });
  });

  // ============================================================
  // getLegacyPlanInfo() Tests
  // ============================================================
  describe('getLegacyPlanInfo()', () => {
    describe('returns correct info for legacy plans', () => {
      it('returns correct object for "identity"', () => {
        const info = getLegacyPlanInfo('identity');
        expect(info).not.toBeNull();
        expect(info).toEqual({
          isLegacy: true,
          displayName: 'Identity Plus (Early Supporter)',
          tier: 'single_team',
        });
      });

      it('has isLegacy set to true', () => {
        const info = getLegacyPlanInfo('identity');
        expect(info?.isLegacy).toBe(true);
      });

      it('maps to single_team tier for feature parity', () => {
        const info = getLegacyPlanInfo('identity');
        expect(info?.tier).toBe('single_team');
      });

      it('has correct display name with Early Supporter suffix', () => {
        const info = getLegacyPlanInfo('identity');
        expect(info?.displayName).toBe('Identity Plus (Early Supporter)');
      });
    });

    describe('returns null for non-legacy plans', () => {
      it('returns null for "identity_plus_v1_monthly"', () => {
        expect(getLegacyPlanInfo('identity_plus_v1_monthly')).toBeNull();
      });

      it('returns null for "free_v1"', () => {
        expect(getLegacyPlanInfo('free_v1')).toBeNull();
      });

      it('returns null for "team_plus_v1_monthly"', () => {
        expect(getLegacyPlanInfo('team_plus_v1_monthly')).toBeNull();
      });

      it('returns null for empty string', () => {
        expect(getLegacyPlanInfo('')).toBeNull();
      });

      it('returns null for null/undefined', () => {
        expect(getLegacyPlanInfo(null as unknown as string)).toBeNull();
        expect(getLegacyPlanInfo(undefined as unknown as string)).toBeNull();
      });
    });
  });

  // ============================================================
  // getPlanDisplayName() Tests
  // ============================================================
  describe('getPlanDisplayName()', () => {
    describe('legacy plan display names', () => {
      it('"identity" returns "Identity Plus (Early Supporter)"', () => {
        expect(getPlanDisplayName('identity')).toBe('Identity Plus (Early Supporter)');
      });
    });

    describe('current plan display names (existing behavior preserved)', () => {
      it('"identity_plus_v1_monthly" returns "Identity Plus"', () => {
        expect(getPlanDisplayName('identity_plus_v1_monthly')).toBe('Identity Plus');
      });

      it('"identity_plus_v1_yearly" returns "Identity Plus"', () => {
        expect(getPlanDisplayName('identity_plus_v1_yearly')).toBe('Identity Plus');
      });

      it('"free_v1" returns "Free"', () => {
        expect(getPlanDisplayName('free_v1')).toBe('Free');
      });

      it('"free" returns "Free"', () => {
        expect(getPlanDisplayName('free')).toBe('Free');
      });

      it('"team_plus_v1_monthly" returns "Team Plus"', () => {
        expect(getPlanDisplayName('team_plus_v1_monthly')).toBe('Team Plus');
      });

      it('"multi_team_v1_monthly" returns "Team Plus"', () => {
        expect(getPlanDisplayName('multi_team_v1_monthly')).toBe('Team Plus');
      });

      it('"single_team_v1_monthly" returns "Single Team"', () => {
        expect(getPlanDisplayName('single_team_v1_monthly')).toBe('Single Team');
      });
    });

    describe('edge cases', () => {
      it('empty string returns "Free"', () => {
        expect(getPlanDisplayName('')).toBe('Free');
      });

      it('null returns "Free"', () => {
        // getPlanDisplayName handles null/undefined gracefully
        expect(getPlanDisplayName(null as unknown as string)).toBe('Free');
      });

      it('undefined returns "Free"', () => {
        // getPlanDisplayName handles null/undefined gracefully
        expect(getPlanDisplayName(undefined as unknown as string)).toBe('Free');
      });

      it('unknown plan falls back to Title Case conversion', () => {
        // Should strip version/interval suffix and convert to Title Case
        expect(getPlanDisplayName('some_plan_v1_monthly')).toBe('Some Plan');
        expect(getPlanDisplayName('custom_enterprise_v2_yearly')).toBe('Custom Enterprise');
      });
    });

    describe('pattern matching order', () => {
      // Verifies that more specific patterns match before general ones
      it('"identity_plus" matches before "identity"', () => {
        expect(getPlanDisplayName('identity_plus_v1_monthly')).toBe('Identity Plus');
        expect(getPlanDisplayName('identity_plus_v2_yearly')).toBe('Identity Plus');
      });

      it('"identity" exact match shows Early Supporter suffix', () => {
        // Only exact 'identity' should get the Early Supporter treatment
        expect(getPlanDisplayName('identity')).toBe('Identity Plus (Early Supporter)');
      });

      it('free pattern takes precedence', () => {
        expect(getPlanDisplayName('free_v1')).toBe('Free');
        expect(getPlanDisplayName('free_v2_monthly')).toBe('Free');
      });
    });
  });

  // ============================================================
  // Integration: Legacy Plan Tier Mapping
  // ============================================================
  describe('Legacy Plan Tier Mapping', () => {
    /**
     * This tests the logic that PlanSelector.vue uses to map legacy planid
     * to currentTier. The component has this logic:
     *
     * if (planid === 'identity') return 'single_team';
     *
     * We verify that getLegacyPlanInfo provides the correct tier.
     */
    it('legacy "identity" plan maps to "single_team" tier', () => {
      const info = getLegacyPlanInfo('identity');
      expect(info?.tier).toBe('single_team');
    });

    it('tier mapping enables correct upgrade/downgrade behavior', () => {
      const legacyInfo = getLegacyPlanInfo('identity');
      const legacyTier = legacyInfo?.tier ?? 'free';

      // Legacy identity users (single_team tier) can:
      // - Upgrade to multi_team
      // - Downgrade to free
      // - NOT upgrade to single_team (same tier)
      expect(legacyTier).toBe('single_team');
    });
  });
});

// ============================================================
// PlanSelector currentTier Logic Tests
// ============================================================
describe('PlanSelector currentTier Logic', () => {
  /**
   * Extracted logic from PlanSelector.vue currentTier computed property.
   * This tests the tier resolution for various planid values including legacy plans.
   */

  // Mock plan data for testing
  type MockPlan = { id: string; tier: string };
  const mockPlans: MockPlan[] = [
    { id: 'free_v1', tier: 'free' },
    { id: 'identity_plus_v1_monthly', tier: 'single_team' },
    { id: 'identity_plus_v1_yearly', tier: 'single_team' },
    { id: 'team_plus_v1_monthly', tier: 'multi_team' },
    { id: 'team_plus_v1_yearly', tier: 'multi_team' },
  ];

  /**
   * Replicates PlanSelector.vue currentTier logic
   */
  function getCurrentTier(planid: string | null | undefined, plans: MockPlan[]): string {
    if (!planid) return 'free';

    // Find the plan that matches the org's planid to get its tier
    const matchingPlan = plans.find(p => p.id === planid);
    if (matchingPlan) return matchingPlan.tier;

    // Handle legacy plans that aren't in the active plans list
    if (planid === 'identity') return 'single_team';

    // Fallback: infer tier from planid naming convention
    if (planid.includes('multi_team') || planid.includes('team_plus')) return 'multi_team';
    if (planid.includes('single_team') || planid.includes('identity_plus')) return 'single_team';

    return 'free';
  }

  describe('currentTier resolution', () => {
    it('returns "free" for null planid', () => {
      expect(getCurrentTier(null, mockPlans)).toBe('free');
    });

    it('returns "free" for undefined planid', () => {
      expect(getCurrentTier(undefined, mockPlans)).toBe('free');
    });

    it('returns "free" for empty string planid', () => {
      expect(getCurrentTier('', mockPlans)).toBe('free');
    });

    it('returns correct tier for plans in the list', () => {
      expect(getCurrentTier('free_v1', mockPlans)).toBe('free');
      expect(getCurrentTier('identity_plus_v1_monthly', mockPlans)).toBe('single_team');
      expect(getCurrentTier('team_plus_v1_monthly', mockPlans)).toBe('multi_team');
    });

    it('returns "single_team" for legacy "identity" planid', () => {
      // Legacy plan not in active plans list but has special handling
      expect(getCurrentTier('identity', mockPlans)).toBe('single_team');
    });

    it('infers tier from naming convention for unknown plans', () => {
      // Plans not in list but follow naming convention
      expect(getCurrentTier('identity_plus_v2_monthly', mockPlans)).toBe('single_team');
      expect(getCurrentTier('team_plus_v2_yearly', mockPlans)).toBe('multi_team');
      expect(getCurrentTier('multi_team_v1_monthly', mockPlans)).toBe('multi_team');
      expect(getCurrentTier('single_team_v1_monthly', mockPlans)).toBe('single_team');
    });
  });

  describe('legacy plan upgrade/downgrade eligibility', () => {
    // Tier order for reference: free < single_team < multi_team

    function canUpgrade(currentTier: string, targetTier: string): boolean {
      if (currentTier === 'free') return targetTier !== 'free';
      if (currentTier === 'single_team') return targetTier === 'multi_team';
      return false;
    }

    function canDowngrade(currentTier: string, targetTier: string): boolean {
      if (currentTier === 'multi_team') return targetTier !== 'multi_team';
      if (currentTier === 'single_team') return targetTier === 'free';
      return false;
    }

    it('legacy "identity" users can upgrade to multi_team', () => {
      const legacyTier = getCurrentTier('identity', mockPlans);
      expect(canUpgrade(legacyTier, 'multi_team')).toBe(true);
    });

    it('legacy "identity" users can downgrade to free', () => {
      const legacyTier = getCurrentTier('identity', mockPlans);
      expect(canDowngrade(legacyTier, 'free')).toBe(true);
    });

    it('legacy "identity" users cannot upgrade to single_team (same tier)', () => {
      const legacyTier = getCurrentTier('identity', mockPlans);
      expect(canUpgrade(legacyTier, 'single_team')).toBe(false);
    });

    it('legacy "identity" users cannot downgrade to single_team (same tier)', () => {
      const legacyTier = getCurrentTier('identity', mockPlans);
      expect(canDowngrade(legacyTier, 'single_team')).toBe(false);
    });
  });
});

// ============================================================
// OrganizationsSettings Badge Logic Tests
// ============================================================
describe('OrganizationsSettings Badge Logic', () => {
  /**
   * Tests the logic for displaying badges in OrganizationsSettings.vue.
   * This includes:
   * - "PRO" badge for paid plans
   * - Plan display names (which show "Early Supporter" for legacy plans)
   */

  /**
   * Replicates hasPaidPlan() from OrganizationsSettings.vue
   */
  function hasPaidPlan(planid: string | null | undefined): boolean {
    if (!planid) return false;
    return !planid.toLowerCase().startsWith('free');
  }

  describe('hasPaidPlan()', () => {
    it('returns true for legacy "identity" plan', () => {
      expect(hasPaidPlan('identity')).toBe(true);
    });

    it('returns true for "identity_plus_v1_monthly"', () => {
      expect(hasPaidPlan('identity_plus_v1_monthly')).toBe(true);
    });

    it('returns true for "team_plus_v1_monthly"', () => {
      expect(hasPaidPlan('team_plus_v1_monthly')).toBe(true);
    });

    it('returns false for "free_v1"', () => {
      expect(hasPaidPlan('free_v1')).toBe(false);
    });

    it('returns false for "free"', () => {
      expect(hasPaidPlan('free')).toBe(false);
    });

    it('returns false for null/undefined/empty', () => {
      expect(hasPaidPlan(null)).toBe(false);
      expect(hasPaidPlan(undefined)).toBe(false);
      expect(hasPaidPlan('')).toBe(false);
    });
  });

  describe('Plan display name for organization cards', () => {
    it('legacy "identity" shows "Identity Plus (Early Supporter)"', () => {
      const displayName = getPlanDisplayName('identity');
      expect(displayName).toBe('Identity Plus (Early Supporter)');
      expect(displayName).toContain('Early Supporter');
    });

    it('current "identity_plus_v1_monthly" shows "Identity Plus" (no suffix)', () => {
      const displayName = getPlanDisplayName('identity_plus_v1_monthly');
      expect(displayName).toBe('Identity Plus');
      expect(displayName).not.toContain('Early Supporter');
    });

    it('free plan shows "Free"', () => {
      expect(getPlanDisplayName('free_v1')).toBe('Free');
    });
  });

  describe('Badge visibility for organization types', () => {
    // Simulates what badges would be shown for different org configs
    interface OrgConfig {
      planid: string | null;
      is_default: boolean;
    }

    function getBadges(org: OrgConfig): string[] {
      const badges: string[] = [];
      if (hasPaidPlan(org.planid)) badges.push('PRO');
      if (org.is_default) badges.push('Default');
      return badges;
    }

    it('legacy "identity" org shows PRO badge', () => {
      const badges = getBadges({ planid: 'identity', is_default: false });
      expect(badges).toContain('PRO');
    });

    it('free org does not show PRO badge', () => {
      const badges = getBadges({ planid: 'free_v1', is_default: false });
      expect(badges).not.toContain('PRO');
    });

    it('paid non-legacy org shows PRO badge', () => {
      const badges = getBadges({ planid: 'identity_plus_v1_monthly', is_default: false });
      expect(badges).toContain('PRO');
    });

    it('default org shows both PRO and Default badges when paid', () => {
      const badges = getBadges({ planid: 'identity', is_default: true });
      expect(badges).toContain('PRO');
      expect(badges).toContain('Default');
    });
  });
});
