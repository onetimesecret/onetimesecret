// src/apps/workspace/composables/useDashboardMode.ts

import { computed } from 'vue';
import { storeToRefs } from 'pinia';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useEntitlements } from '@/shared/composables/useEntitlements';

export type DashboardVariant = 'basic';

/**
 * Determines which dashboard variant to display.
 *
 * With Teams removed, this now always returns 'basic' variant.
 * This composable is kept for compatibility but simplified.
 */
export function useDashboardMode() {
  const orgStore = useOrganizationStore();
  const { currentOrganization } = storeToRefs(orgStore);
  const { isStandaloneMode } = useEntitlements(currentOrganization);

  // Always basic variant now
  const variant = computed<DashboardVariant>(() => 'basic');

  // Computed key for transitions
  const transitionKey = computed(() => {
    const mode = isStandaloneMode.value ? 'standalone' : 'hosted';
    return `${mode}-${variant.value}`;
  });

  return {
    variant,
    transitionKey,
  };
}
