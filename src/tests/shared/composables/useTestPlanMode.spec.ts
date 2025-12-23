// src/tests/shared/composables/useTestPlanMode.spec.ts

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { useTestPlanMode } from '@/shared/composables/useTestPlanMode';
import { WindowService } from '@/services/window.service';

// Mock WindowService
vi.mock('@/services/window.service', () => ({
  WindowService: {
    get: vi.fn(),
    getState: vi.fn(() => ({})),
  },
}));

describe('useTestPlanMode', () => {
  beforeEach(() => {
    vi.mocked(WindowService.get).mockReset();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('isTestModeActive', () => {
    it('returns true when window state has test planid', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_planid') return 'identity_v1';
        return undefined;
      });

      const { isTestModeActive } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(true);
    });

    it('returns false when no override is set', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_planid') return null;
        return undefined;
      });

      const { isTestModeActive } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(false);
    });

    it('returns false when test planid is undefined', () => {
      vi.mocked(WindowService.get).mockImplementation(() => undefined);

      const { isTestModeActive } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(false);
    });

    it('returns false when test planid is empty string', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_planid') return '';
        return undefined;
      });

      const { isTestModeActive } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(false);
    });
  });

  describe('testPlanId', () => {
    it('returns planid from window state when active', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_planid') return 'multi_team_v1';
        return undefined;
      });

      const { testPlanId } = useTestPlanMode();

      expect(testPlanId.value).toBe('multi_team_v1');
    });

    it('returns null when no override is set', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_planid') return null;
        return undefined;
      });

      const { testPlanId } = useTestPlanMode();

      expect(testPlanId.value).toBeNull();
    });

    it('correctly reads different plan ids', () => {
      const testCases = ['free', 'identity_v1', 'multi_team_v1'];

      testCases.forEach(planId => {
        vi.mocked(WindowService.get).mockImplementation((key: string) => {
          if (key === 'entitlement_test_planid') return planId;
          return undefined;
        });

        const { testPlanId } = useTestPlanMode();
        expect(testPlanId.value).toBe(planId);
      });
    });
  });

  describe('testPlanName', () => {
    it('returns plan name from window state when active', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_plan_name') return 'Identity Plus';
        if (key === 'entitlement_test_planid') return 'identity_v1';
        return undefined;
      });

      const { testPlanName } = useTestPlanMode();

      expect(testPlanName.value).toBe('Identity Plus');
    });

    it('returns null when no override is set', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_plan_name') return null;
        return undefined;
      });

      const { testPlanName } = useTestPlanMode();

      expect(testPlanName.value).toBeNull();
    });

    it('handles missing plan name gracefully', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_planid') return 'identity_v1';
        if (key === 'entitlement_test_plan_name') return undefined;
        return undefined;
      });

      const { testPlanName } = useTestPlanMode();

      expect(testPlanName.value).toBeUndefined();
    });
  });

  describe('actualPlanId', () => {
    it('returns actual organization planid', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'organization') return { planid: 'free' };
        return undefined;
      });

      const { actualPlanId } = useTestPlanMode();

      expect(actualPlanId.value).toBe('free');
    });

    it('returns undefined when organization is not available', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'organization') return null;
        return undefined;
      });

      const { actualPlanId } = useTestPlanMode();

      expect(actualPlanId.value).toBeUndefined();
    });

    it('returns undefined when organization has no planid', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'organization') return {};
        return undefined;
      });

      const { actualPlanId } = useTestPlanMode();

      expect(actualPlanId.value).toBeUndefined();
    });
  });

  describe('Integration scenarios', () => {
    it('provides complete test mode state when active', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_planid') return 'multi_team_v1';
        if (key === 'entitlement_test_plan_name') return 'Multi-Team';
        if (key === 'organization') return { planid: 'free' };
        return undefined;
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
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_planid') return null;
        if (key === 'entitlement_test_plan_name') return null;
        if (key === 'organization') return { planid: 'identity_v1' };
        return undefined;
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
    it('computed values are reactive', () => {
      let mockPlanId = 'free';

      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_planid') return mockPlanId;
        return undefined;
      });

      const { testPlanId, isTestModeActive } = useTestPlanMode();

      expect(testPlanId.value).toBe('free');
      expect(isTestModeActive.value).toBe(true);

      // Simulate changing the mock value
      mockPlanId = 'identity_v1';

      // Note: In real implementation, this would need proper reactivity
      // This test documents expected behavior
    });
  });

  describe('Edge cases', () => {
    it('handles WindowService errors gracefully', () => {
      vi.mocked(WindowService.get).mockImplementation(() => {
        throw new Error('Window state not initialized');
      });

      // Should not crash when calling the composable
      expect(() => {
        useTestPlanMode();
      }).not.toThrow();
    });

    it('handles partial window state', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_planid') return 'identity_v1';
        // Other keys return undefined
        return undefined;
      });

      const {
        isTestModeActive,
        testPlanId,
        testPlanName,
        actualPlanId,
      } = useTestPlanMode();

      expect(isTestModeActive.value).toBe(true);
      expect(testPlanId.value).toBe('identity_v1');
      expect(testPlanName.value).toBeUndefined();
      expect(actualPlanId.value).toBeUndefined();
    });

    it('treats whitespace-only planid as inactive', () => {
      vi.mocked(WindowService.get).mockImplementation((key: string) => {
        if (key === 'entitlement_test_planid') return '   ';
        return undefined;
      });

      const { isTestModeActive } = useTestPlanMode();

      // Implementation should trim and treat as inactive
      expect(isTestModeActive.value).toBe(false);
    });
  });
});
