<!-- src/apps/workspace/dashboard/DashboardMain.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useDashboardMode } from '@/apps/workspace/composables/useDashboardMode';

  // Dashboard variants
  import DashboardBasic from './DashboardBasic.vue';
  import DashboardEmpty from './DashboardEmpty.vue';
  import DashboardIndex from './DashboardIndex.vue';
  import SingleTeamDashboard from './SingleTeamDashboard.vue';
  import DashboardSkeleton from './DashboardSkeleton.vue';

  const { t } = useI18n();

  const {
    variant,
    transitionKey,
    teamsLoading,
    fetchError,
    hasTeamCapability,
    fetchTeams,
  } = useDashboardMode();
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
        @click="fetchTeams"
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

    <!-- Loading skeleton - shows placeholder while teams fetch -->
    <DashboardSkeleton v-else-if="variant === 'loading'" />

    <!-- Normal dashboard variants rendered inline -->
    <Transition
      v-else
      name="dashboard-fade"
      mode="out-in">
      <!-- No team capability: basic dashboard with upgrade prompt -->
      <DashboardBasic
        v-if="variant === 'basic'"
        :key="transitionKey" />

      <!-- Has team capability, no teams yet: onboarding -->
      <DashboardEmpty
        v-else-if="variant === 'empty'"
        :key="transitionKey" />

      <!-- Has team capability, single team: focused view -->
      <SingleTeamDashboard
        v-else-if="variant === 'single'"
        :key="transitionKey" />

      <!-- Has team capability, multiple teams: full hub -->
      <DashboardIndex
        v-else-if="variant === 'multi'"
        :key="transitionKey" />
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
