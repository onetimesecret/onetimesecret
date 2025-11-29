<!-- src/views/dashboard/DashboardContainer.vue -->

<script setup lang="ts">
  import { useCapabilities } from '@/composables/useCapabilities';
  import { WindowService } from '@/services/window.service';
  import { useOrganizationStore } from '@/stores/organizationStore';
  import { useTeamStore } from '@/stores/teamStore';
  import { CAPABILITIES } from '@/types/organization';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';

  // Dashboard variants
  import DashboardBasic from './DashboardBasic.vue';
  import DashboardEmpty from './DashboardEmpty.vue';
  import DashboardIndex from './DashboardIndex.vue';
  import SingleTeamDashboard from './SingleTeamDashboard.vue';

  const orgStore = useOrganizationStore();
  const teamStore = useTeamStore();
  const { currentOrganization } = storeToRefs(orgStore);
  const { teams, loading: teamsLoading } = storeToRefs(teamStore);
  const { can } = useCapabilities(currentOrganization);

  // Track if initial team fetch is complete
  const teamsLoaded = ref(false);

  // Check if billing is enabled (for SaaS vs self-hosted distinction)
  const billingEnabled = computed(() => WindowService.get('billing_enabled') || false);

  // Self-hosted mode: billing disabled means full access
  const isOpensourceMode = computed(() => !billingEnabled.value);

  // Team count for experience adaptation
  const teamCount = computed(() => teams.value.length);

  // Check if user has team management capabilities
  const hasTeamCapability = computed(() => {
    // Opensource mode: all capabilities available
    if (isOpensourceMode.value) return true;

    // SaaS: check actual capabilities
    return can(CAPABILITIES.CREATE_TEAM) || can(CAPABILITIES.CREATE_TEAMS);
  });

  /**
   * Experience Selection Logic:
   *
   * Capabilities GATE what features are available.
   * Team count ADAPTS the UX to actual usage.
   *
   * | Capability     | Team Count | Experience           |
   * |----------------|------------|----------------------|
   * | No team cap    | any        | DashboardBasic       |
   * | Has team cap   | 0          | DashboardEmpty       |
   * | Has team cap   | 1          | SingleTeamDashboard  |
   * | Has team cap   | 2+         | DashboardIndex       |
   *
   * Self-hosted always has team capability via backend fallback.
   */
  const dashboardComponent = computed(() => {
    // Wait for teams to load before making team-count decisions
    if (!teamsLoaded.value && teamsLoading.value) {
      // Show basic while loading to avoid flash
      return DashboardBasic;
    }

    // No team capability → basic dashboard with upgrade prompt
    if (!hasTeamCapability.value) {
      return DashboardBasic;
    }

    // Has team capability - adapt based on team count
    if (teamCount.value === 0) {
      // Onboarding: encourage creating first team
      return DashboardEmpty;
    }

    if (teamCount.value === 1) {
      // Focused: single team quick access
      return SingleTeamDashboard;
    }

    // Multi-team: full hub with team grid
    return DashboardIndex;
  });

  // Derive variant name for transition key (avoids re-render when 2→3→4 teams)
  const dashboardVariant = computed(() => {
    if (!teamsLoaded.value && teamsLoading.value) return 'loading';
    if (!hasTeamCapability.value) return 'basic';
    if (teamCount.value === 0) return 'empty';
    if (teamCount.value === 1) return 'single';
    return 'multi';
  });

  // Computed key for transitions - only changes when variant changes
  const componentKey = computed(() => {
    const mode = isOpensourceMode.value ? 'opensource' : 'saas';
    return `${mode}-${dashboardVariant.value}`;
  });

  // Fetch teams on mount
  onMounted(async () => {
    try {
      await teamStore.fetchTeams();
    } catch {
      // Silently fail - experience will adapt to 0 teams
    } finally {
      teamsLoaded.value = true;
    }
  });
</script>

<template>
  <div class="dashboard-container">
    <Transition name="dashboard-fade" mode="out-in">
      <Component
        :key="componentKey"
        :is="dashboardComponent" />
    </Transition>
  </div>
</template>

<style scoped>
.dashboard-container {
  min-height: 400px;
  position: relative;
}

.dashboard-fade-enter-active,
.dashboard-fade-leave-active {
  transition: opacity 0.2s ease;
}

.dashboard-fade-enter-from,
.dashboard-fade-leave-to {
  opacity: 0;
}
</style>
