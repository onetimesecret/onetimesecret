// src/apps/workspace/composables/useDashboardMode.ts

import { computed, ref, onMounted } from 'vue';
import { storeToRefs } from 'pinia';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useTeamStore } from '@/shared/stores/teamStore';
import { useEntitlements } from '@/shared/composables/useEntitlements';
import { ENTITLEMENTS } from '@/types/organization';

export type DashboardVariant = 'loading' | 'basic' | 'empty' | 'single' | 'multi';

/**
 * Determines which dashboard variant to display based on entitlements and team count.
 *
 * Entitlements GATE what features are available.
 * Team count ADAPTS the UX to actual usage.
 *
 * | Entitlement     | Team Count | Variant              |
 * |----------------|------------|----------------------|
 * | No team cap    | any        | basic                |
 * | Has team cap   | 0          | empty                |
 * | Has team cap   | 1          | single               |
 * | Has team cap   | 2+         | multi                |
 *
 * Standalone mode always has team entitlement via backend fallback.
 */
export function useDashboardMode() {
  const orgStore = useOrganizationStore();
  const teamStore = useTeamStore();
  const { currentOrganization } = storeToRefs(orgStore);
  const { teams, loading: teamsLoading } = storeToRefs(teamStore);
  const { can, isStandaloneMode } = useEntitlements(currentOrganization);

  // Track if initial team fetch is complete
  const teamsLoaded = ref(false);
  const fetchError = ref(false);

  // Team count for experience adaptation
  const teamCount = computed(() => teams.value.length);

  // Check if user has team management entitlements
  const hasTeamEntitlement = computed(() => {
    // Standalone mode: all entitlements available
    if (isStandaloneMode.value) return true;

    // Check actual entitlements
    return can(ENTITLEMENTS.MANAGE_TEAMS);
  });

  /**
   * Determines which dashboard variant to render.
   */
  const variant = computed<DashboardVariant>(() => {
    // Wait for teams to load before making team-count decisions
    if (!teamsLoaded.value && teamsLoading.value) {
      return 'loading';
    }

    // No team entitlement → basic dashboard with upgrade prompt
    if (!hasTeamEntitlement.value) {
      return 'basic';
    }

    // Has team entitlement - adapt based on team count
    if (teamCount.value === 0) {
      return 'empty';
    }

    if (teamCount.value === 1) {
      return 'single';
    }

    return 'multi';
  });

  // Computed key for transitions - only changes when variant changes
  const transitionKey = computed(() => {
    const mode = isStandaloneMode.value ? 'standalone' : 'hosted';
    return `${mode}-${variant.value}`;
  });

  // Fetch teams with error handling
  const fetchTeams = async () => {
    fetchError.value = false;
    try {
      await teamStore.fetchTeams();
    } catch {
      fetchError.value = true;
    } finally {
      teamsLoaded.value = true;
    }
  };

  // Auto-fetch on mount
  onMounted(fetchTeams);

  return {
    variant,
    transitionKey,
    teamsLoading,
    teamsLoaded,
    fetchError,
    hasTeamEntitlement,
    fetchTeams,
  };
}
