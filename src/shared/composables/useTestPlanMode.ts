// src/shared/composables/useTestPlanMode.ts
//
// Focused composable for colonel test plan mode.
// Provides a clean API for checking and displaying test mode state.

import { computed } from 'vue';
import { WindowService } from '@/services/window.service';

/**
 * Composable for colonel test plan mode state.
 *
 * Allows colonels to temporarily override their organization's plan
 * for testing entitlement-gated features.
 */
export function useTestPlanMode() {
  /**
   * Get test plan ID from window state
   */
  const testPlanId = computed(() => {
    try {
      return WindowService.get('entitlement_test_planid') || null;
    } catch {
      return null;
    }
  });

  /**
   * Check if test mode is active
   * Returns false for null, undefined, empty string, or whitespace-only
   */
  const isTestModeActive = computed(() => {
    const planId = testPlanId.value;
    if (!planId) return false;
    return planId.trim().length > 0;
  });

  /**
   * Get test plan name from window state
   */
  const testPlanName = computed(() => {
    try {
      return WindowService.get('entitlement_test_plan_name');
    } catch {
      return null;
    }
  });

  /**
   * Get actual organization plan ID (not the test override)
   */
  const actualPlanId = computed(() => {
    try {
      const org = WindowService.get('organization');
      return org?.planid;
    } catch {
      return undefined;
    }
  });

  return {
    isTestModeActive,
    testPlanId,
    testPlanName,
    actualPlanId,
  };
}
