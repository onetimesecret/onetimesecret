// src/tests/shared/composables/useTestPlanMode.spec.ts

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useTestPlanMode } from '@/shared/composables/useTestPlanMode';

describe('useTestPlanMode', () => {
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  /**
   * Helper to set up bootstrapStore with test plan mode configuration
   */
  function setupBootstrapStore(config: {
    entitlement_test_planid?: string | null;
    entitlement_test_plan_name?: string | null;
    organization?: { planid?: string } | null;
  } = {}) {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });
    setActivePinia(pinia);

    bootstrapStore = useBootstrapStore();
    bootstrapStore.entitlement_test_planid = config.entitlement_test_planid;
    bootstrapStore.entitlement_test_plan_name = config.entitlement_test_plan_name;
    bootstrapStore.organization = config.organization as any;

    return { pinia, bootstrapStore };
  }

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('isTestModeActive', () => {
    it('returns true when window state has test planid', () => {
      setupBootstrapStore({
        entitlement_test_planid: 'identity_v1',
      });

      const { isTestModeActive } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(true);
    });

    it('returns false when no override is set', () => {
      setupBootstrapStore({
        entitlement_test_planid: null,
      });

      const { isTestModeActive } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(false);
    });

    it('returns false when test planid is undefined', () => {
      setupBootstrapStore({
        entitlement_test_planid: undefined,
      });

      const { isTestModeActive } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(false);
    });

    it('returns false when test planid is empty string', () => {
      setupBootstrapStore({
        entitlement_test_planid: '',
      });

      const { isTestModeActive } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(false);
    });
  });

  describe('testPlanId', () => {
    it('returns planid from window state when active', () => {
      setupBootstrapStore({
        entitlement_test_planid: 'multi_team_v1',
      });

      const { testPlanId } = useTestPlanMode();

      expect(testPlanId.value).toBe('multi_team_v1');
    });

    it('returns null when no override is set', () => {
      setupBootstrapStore({
        entitlement_test_planid: null,
      });

      const { testPlanId } = useTestPlanMode();

      expect(testPlanId.value).toBeNull();
    });

    it('correctly reads different plan ids', () => {
      const testCases = ['free', 'identity_v1', 'multi_team_v1'];

      testCases.forEach(planId => {
        setupBootstrapStore({
          entitlement_test_planid: planId,
        });

        const { testPlanId } = useTestPlanMode();
        expect(testPlanId.value).toBe(planId);
      });
    });
  });

  describe('testPlanName', () => {
    it('returns plan name from window state when active', () => {
      setupBootstrapStore({
        entitlement_test_planid: 'identity_v1',
        entitlement_test_plan_name: 'Identity Plus',
      });

      const { testPlanName } = useTestPlanMode();

      expect(testPlanName.value).toBe('Identity Plus');
    });

    it('returns null when no override is set', () => {
      setupBootstrapStore({
        entitlement_test_plan_name: null,
      });

      const { testPlanName } = useTestPlanMode();

      expect(testPlanName.value).toBeNull();
    });

    it('handles missing plan name gracefully', () => {
      setupBootstrapStore({
        entitlement_test_planid: 'identity_v1',
        entitlement_test_plan_name: undefined,
      });

      const { testPlanName } = useTestPlanMode();

      expect(testPlanName.value).toBeNull();
    });
  });

  describe('actualPlanId', () => {
    it('returns actual organization planid', () => {
      setupBootstrapStore({
        organization: { planid: 'free' },
      });

      const { actualPlanId } = useTestPlanMode();

      expect(actualPlanId.value).toBe('free');
    });

    it('returns undefined when organization is not available', () => {
      setupBootstrapStore({
        organization: null,
      });

      const { actualPlanId } = useTestPlanMode();

      expect(actualPlanId.value).toBeUndefined();
    });

    it('returns undefined when organization has no planid', () => {
      setupBootstrapStore({
        organization: {},
      });

      const { actualPlanId } = useTestPlanMode();

      expect(actualPlanId.value).toBeUndefined();
    });
  });

  describe('Integration scenarios', () => {
    it('provides complete test mode state when active', () => {
      setupBootstrapStore({
        entitlement_test_planid: 'multi_team_v1',
        entitlement_test_plan_name: 'Multi-Team',
        organization: { planid: 'free' },
      });

      const {
        isTestModeActive,
        testPlanId,
        testPlanName,
        actualPlanId,
      } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(true);
      expect(testPlanId.value).toBe('multi_team_v1');
      expect(testPlanName.value).toBe('Multi-Team');
      expect(actualPlanId.value).toBe('free');
    });

    it('provides complete normal state when inactive', () => {
      setupBootstrapStore({
        entitlement_test_planid: null,
        entitlement_test_plan_name: null,
        organization: { planid: 'identity_v1' },
      });

      const {
        isTestModeActive,
        testPlanId,
        testPlanName,
        actualPlanId,
      } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(false);
      expect(testPlanId.value).toBeNull();
      expect(testPlanName.value).toBeNull();
      expect(actualPlanId.value).toBe('identity_v1');
    });
  });

  describe('Reactivity', () => {
    it('computed values are reactive to store changes', () => {
      setupBootstrapStore({
        entitlement_test_planid: 'free',
      });

      const { testPlanId, isTestModeActive } = useTestPlanMode();

      expect(testPlanId.value).toBe('free');
      expect(isTestModeActive.value).toBe(true);

      // Update store value
      bootstrapStore.entitlement_test_planid = 'identity_v1';

      expect(testPlanId.value).toBe('identity_v1');
      expect(isTestModeActive.value).toBe(true);
    });
  });

  describe('Edge cases', () => {
    it('handles partial window state', () => {
      setupBootstrapStore({
        entitlement_test_planid: 'identity_v1',
        // Other keys left undefined
      });

      const {
        isTestModeActive,
        testPlanId,
        testPlanName,
        actualPlanId,
      } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(true);
      expect(testPlanId.value).toBe('identity_v1');
      expect(testPlanName.value).toBeNull();
      expect(actualPlanId.value).toBeUndefined();
    });

    it('treats whitespace-only planid as inactive', () => {
      setupBootstrapStore({
        entitlement_test_planid: '   ',
      });

      const { isTestModeActive } = useTestPlanMode();

      // Implementation should trim and treat as inactive
      expect(isTestModeActive.value).toBe(false);
    });
  });
});
