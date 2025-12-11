// src/apps/workspace/composables/useDashboardMode.ts

import { computed, ref, onMounted } from 'vue';
import { storeToRefs } from 'pinia';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { useTeamStore } from '@/shared/stores/teamStore';
import { useCapabilities } from '@/shared/composables/useCapabilities';
import { CAPABILITIES } from '@/types/organization';

export type DashboardVariant = 'loading' | 'basic' | 'empty' | 'single' | 'multi';

/**
 * Determines which dashboard variant to display based on capabilities and team count.
 *
 * Capabilities GATE what features are available.
 * Team count ADAPTS the UX to actual usage.
 *
 * | Capability     | Team Count | Variant              |
 * |----------------|------------|----------------------|
 * | No team cap    | any        | basic                |
 * | Has team cap   | 0          | empty                |
 * | Has team cap   | 1          | single               |
 * | Has team cap   | 2+         | multi                |
 *
 * Standalone mode always has team capability via backend fallback.
 */
export function useDashboardMode() {
  const orgStore = useOrganizationStore();
  const teamStore = useTeamStore();
  const { currentOrganization } = storeToRefs(orgStore);
  const { teams, loading: teamsLoading } = storeToRefs(teamStore);
  const { can, isStandaloneMode } = useCapabilities(currentOrganization);

  // Track if initial team fetch is complete
  const teamsLoaded = ref(false);
  const fetchError = ref(false);

  // Team count for experience adaptation
  const teamCount = computed(() => teams.value.length);

  // Check if user has team management capabilities
  const hasTeamCapability = computed(() => {
    // Standalone mode: all capabilities available
    if (isStandaloneMode.value) return true;

    // Check actual capabilities
    return can(CAPABILITIES.CREATE_TEAM) || can(CAPABILITIES.CREATE_TEAMS);
  });

  /**
   * Determines which dashboard variant to render.
   */
  const variant = computed<DashboardVariant>(() => {
    // Wait for teams to load before making team-count decisions
    if (!teamsLoaded.value && teamsLoading.value) {
      return 'loading';
    }

    // No team capability → basic dashboard with upgrade prompt
    if (!hasTeamCapability.value) {
      return 'basic';
    }

    // Has team capability - adapt based on team count
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
    hasTeamCapability,
    fetchTeams,
  };
}
