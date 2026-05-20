// src/shared/composables/usePreviewPlanMode.ts

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
export function usePreviewPlanMode() {
  const bootstrapStore = useBootstrapStore();
  const {
    entitlement_preview_planid,
    entitlement_preview_plan_name,
    organization,
  } = storeToRefs(bootstrapStore);

  /**
   * Get test plan ID from bootstrap store
   */
  const previewPlanId = computed(() => entitlement_preview_planid?.value || null);

  /**
   * Check if test mode is active
   * Returns false for null, undefined, empty string, or whitespace-only
   */
  const isPreviewModeActive = computed(() => {
    const planId = previewPlanId.value;
    if (!planId) return false;
    return planId.trim().length > 0;
  });

  /**
   * Get test plan name from bootstrap store
   */
  const previewPlanName = computed(() => entitlement_preview_plan_name?.value ?? null);

  /**
   * Get actual organization plan ID (not the test override)
   */
  const actualPlanId = computed(() => organization?.value?.planid);

  return {
    isPreviewModeActive,
    previewPlanId,
    previewPlanName,
    actualPlanId,
  };
}
