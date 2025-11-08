<!-- src/views/teams/TeamsHub.vue -->
<script setup lang="ts">
import CreateTeamModal from '@/components/teams/CreateTeamModal.vue';
import TeamCard from '@/components/teams/TeamCard.vue';
import UpgradePrompt from '@/components/billing/UpgradePrompt.vue';
import OIcon from '@/components/icons/OIcon.vue';
import { classifyError } from '@/schemas/errors';
import { useTeamStore } from '@/stores/teamStore';
import { useOrganizationStore } from '@/stores/organizationStore';
import { useCapabilities } from '@/composables/useCapabilities';
import { onMounted, ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { storeToRefs } from 'pinia';

const { t } = useI18n();
const router = useRouter();
const teamStore = useTeamStore();
const organizationStore = useOrganizationStore();

const { teams, loading } = storeToRefs(teamStore);
const { currentOrganization } = storeToRefs(organizationStore);

// Capability checking
const { can, hasReachedLimit, limit, upgradePath, CAPABILITIES } = useCapabilities(
  currentOrganization
);

const activeTab = ref<'my-teams' | 'new-team'>('my-teams');
const showCreateModal = ref(false);
const error = ref('');

// Check if user can create teams
const canCreateTeam = computed(() => can(CAPABILITIES.CREATE_TEAM) || can(CAPABILITIES.CREATE_TEAMS));

// Check if team limit has been reached
const teamLimitReached = computed(() => {
  const teamLimit = limit('teams');
  if (teamLimit === 0) return false; // No limit
  return hasReachedLimit('teams', teams.value.length);
});

onMounted(async () => {
  try {
    await teamStore.fetchTeams();
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.userMessage || t('web.teams.fetch_teams_error');
  }
});

const handleTeamClick = (teamId: string) => {
  router.push({ name: 'Team Dashboard', params: { teamid: teamId } });
};

const handleTeamCreated = (teamId: string) => {
  router.push({ name: 'Team Dashboard', params: { teamid: teamId } });
};

const openCreateModal = () => {
  activeTab.value = 'new-team';
  showCreateModal.value = true;
};

const closeCreateModal = () => {
  showCreateModal.value = false;
  activeTab.value = 'my-teams';
};
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
    <!-- Header -->
    <div class="mb-8">
      <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
        {{ t('web.teams.teams') }}
      </h1>
      <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
        {{ t('web.teams.teams_description') }}
      </p>
    </div>

    <!-- Error Alert -->
    <div v-if="error" class="mb-6 rounded-md bg-red-50 p-4 dark:bg-red-900/20">
      <div class="flex">
        <OIcon
          collection="heroicons"
          name="exclamation-circle"
          class="size-5 text-red-400 dark:text-red-300"
          aria-hidden="true"
        />
        <div class="ml-3">
          <p class="text-sm text-red-800 dark:text-red-400">{{ error }}</p>
        </div>
      </div>
    </div>

    <!-- Tabs -->
    <div class="border-b border-gray-200 dark:border-gray-700">
      <nav class="-mb-px flex space-x-8" aria-label="Tabs">
        <button
          @click="activeTab = 'my-teams'"
          :class="[
            'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium transition-colors',
            activeTab === 'my-teams'
              ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
              : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300'
          ]"
        >
          <div class="flex items-center gap-2">
            <OIcon collection="heroicons"
name="users"
class="size-5"
aria-hidden="true" />
            <span>{{ t('web.teams.my_teams') }}</span>
            <span
              v-if="teams.length > 0"
              :class="[
                'ml-2 rounded-full px-2.5 py-0.5 text-xs font-medium',
                activeTab === 'my-teams'
                  ? 'bg-brand-100 text-brand-600 dark:bg-brand-900 dark:text-brand-400'
                  : 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400'
              ]"
            >
              {{ teams.length }}
            </span>
          </div>
        </button>
        <button
          v-if="canCreateTeam && !teamLimitReached"
          @click="openCreateModal"
          :class="[
            'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium transition-colors',
            activeTab === 'new-team'
              ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
              : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300'
          ]"
        >
          <div class="flex items-center gap-2">
            <OIcon collection="heroicons"
name="plus-circle"
class="size-5"
aria-hidden="true" />
            <span>{{ t('web.teams.new_team') }}</span>
          </div>
        </button>
      </nav>
    </div>

    <!-- Content -->
    <div class="mt-8">
      <!-- Upgrade Prompts -->
      <div class="mb-6 space-y-4">
        <!-- No capability to create teams -->
        <UpgradePrompt
          v-if="!canCreateTeam"
          :capability="CAPABILITIES.CREATE_TEAM"
          :upgrade-plan="upgradePath(CAPABILITIES.CREATE_TEAM) || 'multi_team_v1'"
          :message="t('web.billing.upgrade.needTeams')"
        />

        <!-- Team limit reached -->
        <UpgradePrompt
          v-else-if="teamLimitReached"
          :capability="CAPABILITIES.CREATE_TEAMS"
          :upgrade-plan="upgradePath(CAPABILITIES.CREATE_TEAMS) || 'multi_team_v1'"
          :message="t('web.billing.limits.teams_upgrade')"
        />
      </div>

      <!-- My Teams Tab -->
      <div v-if="activeTab === 'my-teams'">
        <!-- Loading State -->
        <div v-if="loading" class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <div
            v-for="i in 3"
            :key="i"
            class="h-40 animate-pulse rounded-lg bg-gray-200 dark:bg-gray-700"
          ></div>
        </div>

        <!-- Teams Grid -->
        <div v-else-if="teams.length > 0" class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          <TeamCard
            v-for="team in teams"
            :key="team.id"
            :team="team"
            @click="handleTeamClick(team.id)"
          />
        </div>

        <!-- Empty State -->
        <div v-else class="text-center">
          <OIcon
            collection="heroicons"
            name="users"
            class="mx-auto size-12 text-gray-400 dark:text-gray-600"
            aria-hidden="true"
          />
          <h3 class="mt-2 text-sm font-medium text-gray-900 dark:text-white">
            {{ t('web.teams.no_teams') }}
          </h3>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.teams.no_teams_description') }}
          </p>
          <div v-if="canCreateTeam && !teamLimitReached" class="mt-6">
            <button
              type="button"
              @click="openCreateModal"
              class="inline-flex items-center rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400"
            >
              <OIcon collection="heroicons"
name="plus"
class="-ml-0.5 mr-1.5 size-5"
aria-hidden="true" />
              {{ t('web.teams.create_team') }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Create Team Modal -->
    <CreateTeamModal
      :open="showCreateModal"
      @close="closeCreateModal"
      @created="handleTeamCreated"
    />
  </div>
</template>
