// src/shared/composables/useTestPlanMode.ts

//
// Focused composable for colonel test plan mode.
// Provides a clean API for checking and displaying test mode state.

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';
import { computed } from 'vue';

/**
 * Composable for colonel test plan mode state.
 *
 * Allows colonels to temporarily override their organization's plan
 * for testing entitlement-gated features.
 */
export function useTestPlanMode() {
  const bootstrapStore = useBootstrapStore();
  const {
    entitlement_test_planid,
    entitlement_test_plan_name,
    organization,
  } = storeToRefs(bootstrapStore);

  /**
   * Get test plan ID from bootstrap store
   */
  const testPlanId = computed(() => entitlement_test_planid.value || null);

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
   * Get test plan name from bootstrap store
   */
  const testPlanName = computed(() => entitlement_test_plan_name.value ?? null);

  /**
   * Get actual organization plan ID (not the test override)
   */
  const actualPlanId = computed(() => organization.value?.planid);

  return {
    isTestModeActive,
    testPlanId,
    testPlanName,
    actualPlanId,
  };
}
