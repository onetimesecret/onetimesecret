// src/tests/shared/composables/usePreviewPlanMode.spec.ts

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { usePreviewPlanMode } from '@/shared/composables/usePreviewPlanMode';

describe('usePreviewPlanMode', () => {
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  /**
   * Helper to set up bootstrapStore with test plan mode configuration
   */
  function setupBootstrapStore(config: {
    entitlement_preview_planid?: string | null;
    entitlement_preview_plan_name?: string | null;
    organization?: { planid?: string } | null;
  } = {}) {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });
    setActivePinia(pinia);

    bootstrapStore = useBootstrapStore();
    bootstrapStore.entitlement_preview_planid = config.entitlement_preview_planid;
    bootstrapStore.entitlement_preview_plan_name = config.entitlement_preview_plan_name;
    bootstrapStore.organization = config.organization as any;

    return { pinia, bootstrapStore };
  }

  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('isPreviewModeActive', () => {
    it('returns true when window state has test planid', () => {
      setupBootstrapStore({
        entitlement_preview_planid: 'identity_v1',
      });

      const { isPreviewModeActive } = usePreviewPlanMode();

      expect(isPreviewModeActive.value).toBe(true);
    });

    it('returns false when no override is set', () => {
      setupBootstrapStore({
        entitlement_preview_planid: null,
      });

      const { isPreviewModeActive } = usePreviewPlanMode();

      expect(isPreviewModeActive.value).toBe(false);
    });

    it('returns false when test planid is undefined', () => {
      setupBootstrapStore({
        entitlement_preview_planid: undefined,
      });

      const { isPreviewModeActive } = usePreviewPlanMode();

      expect(isPreviewModeActive.value).toBe(false);
    });

    it('returns false when test planid is empty string', () => {
      setupBootstrapStore({
        entitlement_preview_planid: '',
      });

      const { isPreviewModeActive } = usePreviewPlanMode();

      expect(isPreviewModeActive.value).toBe(false);
    });
  });

  describe('previewPlanId', () => {
    it('returns planid from window state when active', () => {
      setupBootstrapStore({
        entitlement_preview_planid: 'multi_team_v1',
      });

      const { previewPlanId } = usePreviewPlanMode();

      expect(previewPlanId.value).toBe('multi_team_v1');
    });

    it('returns null when no override is set', () => {
      setupBootstrapStore({
        entitlement_preview_planid: null,
      });

      const { previewPlanId } = usePreviewPlanMode();

      expect(previewPlanId.value).toBeNull();
    });

    it('correctly reads different plan ids', () => {
      const testCases = ['free', 'identity_v1', 'multi_team_v1'];

      testCases.forEach(planId => {
        setupBootstrapStore({
          entitlement_preview_planid: planId,
        });

        const { previewPlanId } = usePreviewPlanMode();
        expect(previewPlanId.value).toBe(planId);
      });
    });
  });

  describe('previewPlanName', () => {
    it('returns plan name from window state when active', () => {
      setupBootstrapStore({
        entitlement_preview_planid: 'identity_v1',
        entitlement_preview_plan_name: 'Identity Plus',
      });

      const { previewPlanName } = usePreviewPlanMode();

      expect(previewPlanName.value).toBe('Identity Plus');
    });

    it('returns null when no override is set', () => {
      setupBootstrapStore({
        entitlement_preview_plan_name: null,
      });

      const { previewPlanName } = usePreviewPlanMode();

      expect(previewPlanName.value).toBeNull();
    });

    it('handles missing plan name gracefully', () => {
      setupBootstrapStore({
        entitlement_preview_planid: 'identity_v1',
        entitlement_preview_plan_name: undefined,
      });

      const { previewPlanName } = usePreviewPlanMode();

      expect(previewPlanName.value).toBeNull();
    });
  });

  describe('actualPlanId', () => {
    it('returns actual organization planid', () => {
      setupBootstrapStore({
        organization: { planid: 'free' },
      });

      const { actualPlanId } = usePreviewPlanMode();

      expect(actualPlanId.value).toBe('free');
    });

    it('returns undefined when organization is not available', () => {
      setupBootstrapStore({
        organization: null,
      });

      const { actualPlanId } = usePreviewPlanMode();

      expect(actualPlanId.value).toBeUndefined();
    });

    it('returns undefined when organization has no planid', () => {
      setupBootstrapStore({
        organization: {},
      });

      const { actualPlanId } = usePreviewPlanMode();

      expect(actualPlanId.value).toBeUndefined();
    });
  });

  describe('Integration scenarios', () => {
    it('provides complete test mode state when active', () => {
      setupBootstrapStore({
        entitlement_preview_planid: 'multi_team_v1',
        entitlement_preview_plan_name: 'Multi-Team',
        organization: { planid: 'free' },
      });

      const {
        isPreviewModeActive,
        previewPlanId,
        previewPlanName,
        actualPlanId,
      } = usePreviewPlanMode();

      expect(isPreviewModeActive.value).toBe(true);
      expect(previewPlanId.value).toBe('multi_team_v1');
      expect(previewPlanName.value).toBe('Multi-Team');
      expect(actualPlanId.value).toBe('free');
    });

    it('provides complete normal state when inactive', () => {
      setupBootstrapStore({
        entitlement_preview_planid: null,
        entitlement_preview_plan_name: null,
        organization: { planid: 'identity_v1' },
      });

      const {
        isPreviewModeActive,
        previewPlanId,
        previewPlanName,
        actualPlanId,
      } = usePreviewPlanMode();

      expect(isPreviewModeActive.value).toBe(false);
      expect(previewPlanId.value).toBeNull();
      expect(previewPlanName.value).toBeNull();
      expect(actualPlanId.value).toBe('identity_v1');
    });
  });

  describe('Reactivity', () => {
    it('computed values are reactive to store changes', () => {
      setupBootstrapStore({
        entitlement_preview_planid: 'free',
      });

      const { previewPlanId, isPreviewModeActive } = usePreviewPlanMode();

      expect(previewPlanId.value).toBe('free');
      expect(isPreviewModeActive.value).toBe(true);

      // Update store value
      bootstrapStore.entitlement_preview_planid = 'identity_v1';

      expect(previewPlanId.value).toBe('identity_v1');
      expect(isPreviewModeActive.value).toBe(true);
    });
  });

  describe('Edge cases', () => {
    it('handles partial window state', () => {
      setupBootstrapStore({
        entitlement_preview_planid: 'identity_v1',
        // Other keys left undefined
      });

      const {
        isPreviewModeActive,
        previewPlanId,
        previewPlanName,
        actualPlanId,
      } = usePreviewPlanMode();

      expect(isPreviewModeActive.value).toBe(true);
      expect(previewPlanId.value).toBe('identity_v1');
      expect(previewPlanName.value).toBeNull();
      expect(actualPlanId.value).toBeUndefined();
    });

    it('treats whitespace-only planid as inactive', () => {
      setupBootstrapStore({
        entitlement_preview_planid: '   ',
      });

      const { isPreviewModeActive } = usePreviewPlanMode();

      // Implementation should trim and treat as inactive
      expect(isPreviewModeActive.value).toBe(false);
    });
  });
});
