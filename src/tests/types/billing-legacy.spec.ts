// src/tests/types/billing-legacy.spec.ts

/**
 * Unit tests for legacy plan detection and display in billing utilities
 *
 * These tests cover the new legacy plan handling functionality:
 * - isLegacyPlan() - detects grandfathered plans
 * - getLegacyPlanInfo() - returns legacy plan metadata
 * - getPlanLabel() - displays legacy plans with special suffix
 *
 * Legacy plans are grandfathered plans no longer available for new subscriptions
 * but honored for existing customers (e.g., 'identity' -> 'Identity Plus (Early Supporter)')
 */

import { describe, it, expect } from 'vitest';
import {
  isLegacyPlan,
  getLegacyPlanInfo,
  getPlanLabel,
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
      it('returns false for "identity_plus_v1"', () => {
        expect(isLegacyPlan('identity_plus_v1')).toBe(false);
      });

      it('returns false for "free_v1"', () => {
        expect(isLegacyPlan('free_v1')).toBe(false);
      });

      it('returns false for "team_plus_v1"', () => {
        expect(isLegacyPlan('team_plus_v1')).toBe(false);
      });

      it('returns false for "single_team_v1"', () => {
        expect(isLegacyPlan('single_team_v1')).toBe(false);
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
          tier: 'single_account',
        });
      });

      it('has isLegacy set to true', () => {
        const info = getLegacyPlanInfo('identity');
        expect(info?.isLegacy).toBe(true);
      });

      it('maps to single_account tier for feature parity (#3824 backend reality)', () => {
        const info = getLegacyPlanInfo('identity');
        expect(info?.tier).toBe('single_account');
      });

      it('has correct display name with Early Supporter suffix', () => {
        const info = getLegacyPlanInfo('identity');
        expect(info?.displayName).toBe('Identity Plus (Early Supporter)');
      });
    });

    describe('returns null for non-legacy plans', () => {
      it('returns null for "identity_plus_v1"', () => {
        expect(getLegacyPlanInfo('identity_plus_v1')).toBeNull();
      });

      it('returns null for "free_v1"', () => {
        expect(getLegacyPlanInfo('free_v1')).toBeNull();
      });

      it('returns null for "team_plus_v1"', () => {
        expect(getLegacyPlanInfo('team_plus_v1')).toBeNull();
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
  // getPlanLabel() Tests
  // ============================================================
  describe('getPlanLabel()', () => {
    describe('legacy plan display names', () => {
      it('"identity" returns "Identity Plus (Early Supporter)"', () => {
        expect(getPlanLabel('identity')).toBe('Identity Plus (Early Supporter)');
      });
    });

    describe('canonical plan ID display names', () => {
      it('"identity_plus_v1" returns "Identity Plus"', () => {
        expect(getPlanLabel('identity_plus_v1')).toBe('Identity Plus');
      });

      it('"free_v1" returns "Free"', () => {
        expect(getPlanLabel('free_v1')).toBe('Free');
      });

      it('"team_plus_v1" returns "Team Plus"', () => {
        expect(getPlanLabel('team_plus_v1')).toBe('Team Plus');
      });

      it('"legacy_plan_v1" returns "Legacy Plan"', () => {
        expect(getPlanLabel('legacy_plan_v1')).toBe('Legacy Plan');
      });
    });

    describe('unmapped values', () => {
      it('returns input unchanged for unmapped plan IDs', () => {
        expect(getPlanLabel('some_plan')).toBe('some_plan');
        expect(getPlanLabel('custom_enterprise')).toBe('custom_enterprise');
      });

      it('returns input unchanged for tier keys (tiers are metadata, not for selection)', () => {
        expect(getPlanLabel('single_team')).toBe('single_team');
        expect(getPlanLabel('multi_team')).toBe('multi_team');
      });
    });
  });

  // ============================================================
  // Integration: Legacy Plan Tier Mapping
  // ============================================================
  describe('Legacy Plan Tier Mapping', () => {
    /**
     * getLegacyPlanInfo is the source of truth for a grandfathered plan's
     * family tier. Post-#3824 the legacy "identity" plan shares the same tier
     * as identity_plus_v1 in the backend, which is single_account (NOT
     * single_team). Note: PlanSelector.vue no longer hardcodes a legacy tier —
     * its currentTier is derived strictly from an id-matched plan (null for
     * unresolved/legacy). This block verifies the family tier metadata only.
     */
    it('legacy "identity" plan maps to "single_account" tier', () => {
      const info = getLegacyPlanInfo('identity');
      expect(info?.tier).toBe('single_account');
    });

    it('tier mapping enables correct upgrade/downgrade behavior', () => {
      const legacyInfo = getLegacyPlanInfo('identity');
      const legacyTier = legacyInfo?.tier ?? 'free';

      // Legacy identity users (single_account tier) can:
      // - Upgrade to single_team or multi_team
      // - Downgrade to free
      // (single_account is a distinct, lower tier than single_team)
      expect(legacyTier).toBe('single_account');
    });
  });
});

// ============================================================
// PlanSelector currentTier Logic Tests
// ============================================================
describe('PlanSelector currentTier Logic', () => {
  /**
   * Family-tier resolution for a given planid. Post-#3824 the component's own
   * currentTier is id-derived (null for unresolved/legacy), so this helper is a
   * standalone resolver of the FAMILY tier a planid belongs to (used for
   * display/feature-parity reasoning), consistent with getLegacyPlanInfo and
   * the corrected backend tiers: identity_plus_v1 => single_account.
   */

  // Mock plan data for testing
  // Plan IDs are now family-keyed without interval suffix.
  // Backend reality (#3824): identity_plus_v1 is single_account (not single_team)
  // and team_plus_v1 is single_team (not multi_team). Mirrors billing.fixture.ts.
  type MockPlan = { id: string; tier: string };
  const mockPlans: MockPlan[] = [
    { id: 'free_v1', tier: 'free' },
    { id: 'identity_plus_v1', tier: 'single_account' },
    { id: 'team_plus_v1', tier: 'single_team' },
  ];

  /**
   * Resolves the family tier for a planid (see block doc).
   */
  function getCurrentTier(planid: string | null | undefined, plans: MockPlan[]): string {
    if (!planid) return 'free';

    // Find the plan that matches the org's planid to get its tier
    const matchingPlan = plans.find(p => p.id === planid);
    if (matchingPlan) return matchingPlan.tier;

    // Handle legacy plans that aren't in the active plans list.
    // Legacy "identity" shares identity_plus_v1's family tier: single_account.
    if (planid === 'identity') return 'single_account';

    // Fallback: infer tier from planid naming convention.
    // #3824: team_plus_* is single_team, not multi_team. Match multi_team first
    // so a literal multi_team_* id still resolves to the top tier.
    if (planid.includes('multi_team')) return 'multi_team';
    if (planid.includes('team_plus') || planid.includes('single_team')) return 'single_team';
    if (planid.includes('single_account') || planid.includes('identity_plus')) return 'single_account';

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
      // #3824: identity_plus_v1 is single_account and team_plus_v1 is single_team
      // in the backend (not single_team / multi_team respectively).
      expect(getCurrentTier('identity_plus_v1', mockPlans)).toBe('single_account');
      expect(getCurrentTier('team_plus_v1', mockPlans)).toBe('single_team');
    });

    it('returns "single_account" for legacy "identity" planid', () => {
      // Legacy plan not in active plans list but has special handling
      expect(getCurrentTier('identity', mockPlans)).toBe('single_account');
    });

    it('infers tier from naming convention for unknown plans', () => {
      // Plans not in list but follow naming convention
      expect(getCurrentTier('identity_plus_v2', mockPlans)).toBe('single_account');
      // #3824: team_plus_* infers to single_team; only a literal multi_team_* id
      // resolves to the top multi_team tier.
      expect(getCurrentTier('team_plus_v2', mockPlans)).toBe('single_team');
      expect(getCurrentTier('multi_team_v1', mockPlans)).toBe('multi_team');
      expect(getCurrentTier('single_team_v1', mockPlans)).toBe('single_team');
    });
  });

  describe('legacy plan upgrade/downgrade eligibility', () => {
    // Canonical tier order (#3824): free < single_account < single_team < multi_team
    const TIER_ORDER = ['free', 'single_account', 'single_team', 'multi_team'];
    const rank = (tier: string): number => TIER_ORDER.indexOf(tier);

    function canUpgrade(currentTier: string, targetTier: string): boolean {
      const c = rank(currentTier);
      const t = rank(targetTier);
      if (c === -1 || t === -1) return false;
      return t > c;
    }

    function canDowngrade(currentTier: string, targetTier: string): boolean {
      const c = rank(currentTier);
      const t = rank(targetTier);
      if (c === -1 || t === -1) return false;
      return t < c;
    }

    it('legacy "identity" users can upgrade to multi_team', () => {
      const legacyTier = getCurrentTier('identity', mockPlans);
      expect(canUpgrade(legacyTier, 'multi_team')).toBe(true);
    });

    it('legacy "identity" users can downgrade to free', () => {
      const legacyTier = getCurrentTier('identity', mockPlans);
      expect(canDowngrade(legacyTier, 'free')).toBe(true);
    });

    it('legacy "identity" users can upgrade to single_team (a higher tier)', () => {
      // #3824: single_account is a distinct, LOWER tier than single_team, so
      // this is a genuine upgrade direction (the old "same tier" premise is gone).
      const legacyTier = getCurrentTier('identity', mockPlans);
      expect(canUpgrade(legacyTier, 'single_team')).toBe(true);
    });

    it('legacy "identity" users cannot downgrade to single_team (a higher tier)', () => {
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

    it('returns true for "identity_plus_v1"', () => {
      expect(hasPaidPlan('identity_plus_v1')).toBe(true);
    });

    it('returns true for "team_plus_v1"', () => {
      expect(hasPaidPlan('team_plus_v1')).toBe(true);
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
      const displayName = getPlanLabel('identity');
      expect(displayName).toBe('Identity Plus (Early Supporter)');
      expect(displayName).toContain('Early Supporter');
    });

    it('current "identity_plus_v1" shows "Identity Plus" (no suffix)', () => {
      const displayName = getPlanLabel('identity_plus_v1');
      expect(displayName).toBe('Identity Plus');
      expect(displayName).not.toContain('Early Supporter');
    });

    it('free plan shows "Free"', () => {
      expect(getPlanLabel('free_v1')).toBe('Free');
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
      const badges = getBadges({ planid: 'identity_plus_v1', is_default: false });
      expect(badges).toContain('PRO');
    });

    it('default org shows both PRO and Default badges when paid', () => {
      const badges = getBadges({ planid: 'identity', is_default: true });
      expect(badges).toContain('PRO');
      expect(badges).toContain('Default');
    });
  });
});
