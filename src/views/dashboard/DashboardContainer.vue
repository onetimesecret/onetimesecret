<!-- src/views/dashboard/DashboardContainer.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { useCapabilities } from '@/composables/useCapabilities';
  import { useOrganizationStore } from '@/stores/organizationStore';
  import { useTeamStore } from '@/stores/teamStore';
  import { CAPABILITIES } from '@/types/organization';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  // Dashboard variants
  import DashboardBasic from './DashboardBasic.vue';
  import DashboardEmpty from './DashboardEmpty.vue';
  import DashboardIndex from './DashboardIndex.vue';
  import SingleTeamDashboard from './SingleTeamDashboard.vue';

  const { t } = useI18n();
  const orgStore = useOrganizationStore();
  const teamStore = useTeamStore();
  const { currentOrganization } = storeToRefs(orgStore);
  const { teams, loading: teamsLoading } = storeToRefs(teamStore);
  const { can, isOpensourceMode } = useCapabilities(currentOrganization);

  // Track if initial team fetch is complete
  const teamsLoaded = ref(false);
  const fetchError = ref(false);

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

  // Fetch teams with error handling
  const fetchTeamsWithRetry = async () => {
    fetchError.value = false;
    try {
      await teamStore.fetchTeams();
    } catch {
      fetchError.value = true;
    } finally {
      teamsLoaded.value = true;
    }
  };

  // Fetch teams on mount
  onMounted(fetchTeamsWithRetry);
</script>

<template>
  <div class="dashboard-container">
    <!-- Error state with retry -->
    <div
      v-if="fetchError && hasTeamCapability"
      class="container mx-auto min-w-[320px] max-w-2xl py-12 text-center">
      <div class="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-red-100 dark:bg-red-900/30">
        <OIcon
          collection="heroicons"
          name="exclamation-triangle"
          class="size-6 text-red-600 dark:text-red-400"
          aria-hidden="true" />
      </div>
      <h2 class="mb-2 text-lg font-semibold text-gray-900 dark:text-white">
        {{ t('web.dashboard.fetch_error_title', 'Unable to load teams') }}
      </h2>
      <p class="mb-6 text-sm text-gray-600 dark:text-gray-400">
        {{ t('web.dashboard.fetch_error_description', 'There was a problem loading your teams. Please try again.') }}
      </p>
      <button
        type="button"
        @click="fetchTeamsWithRetry"
        :disabled="teamsLoading"
        class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
        <OIcon
          v-if="!teamsLoading"
          collection="heroicons"
          name="arrow-path"
          class="size-5"
          aria-hidden="true" />
        {{ teamsLoading ? t('web.COMMON.loading', 'Loading...') : t('web.COMMON.retry', 'Try again') }}
      </button>
    </div>

    <!-- Normal dashboard variants -->
    <Transition
      v-else
      name="dashboard-fade"
      mode="out-in">
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
