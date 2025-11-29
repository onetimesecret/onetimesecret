<!-- src/views/dashboard/DashboardIndex.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import SecretForm from '@/components/secrets/form/SecretForm.vue';
  import RecentSecretsTable from '@/components/secrets/RecentSecretsTable.vue';
  import TeamCard from '@/components/teams/TeamCard.vue';
  import { WindowService } from '@/services/window.service';
  import { useAuthStore } from '@/stores/authStore';
  import { useTeamStore } from '@/stores/teamStore';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import { useRouter } from 'vue-router';

  const { t } = useI18n();
  const cust = WindowService.get('cust');
  const router = useRouter();
  const authStore = useAuthStore();
  const teamStore = useTeamStore();

  const { teams } = storeToRefs(teamStore);

  const isBetaEnabled = computed(() => cust?.feature_flags?.beta ?? false);
  const hasTeams = computed(() => teams.value.length > 0);

  onMounted(async () => {
    if (authStore.isAuthenticated && teams.value.length === 0) {
      await teamStore.fetchTeams().catch(() => {
        // Silently fail
      });
    }
  });

  const navigateToTeam = (teamId: string) => {
    router.push({ name: 'Team View', params: { extid: teamId } });
  };

  const navigateToTeams = () => {
    router.push({ name: 'Teams' });
  };

  const handleCreateSecret = (teamId: string) => {
    router.push({ name: 'Team View', params: { extid: teamId }, hash: '#create-secret' });
  };
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <SecretForm
      class="mb-12"
      :with-generate="true"
      :with-recipient="true" />

    <!-- Teams Section -->
    <div
      v-if="hasTeams"
      class="mb-12">
      <div class="mb-4 flex items-center justify-between">
        <h2 class="text-xl font-medium text-gray-700 dark:text-gray-200">
          {{ t('web.teams.my_teams') }}
        </h2>
        <button
          type="button"
          @click="navigateToTeams"
          class="inline-flex items-center gap-1.5 text-sm text-brand-600 hover:text-brand-700 dark:text-brand-400 dark:hover:text-brand-300">
          {{ t('web.teams.view_all') }}
          <OIcon
            collection="heroicons"
            name="arrow-right"
            class="size-4"
            aria-hidden="true" />
        </button>
      </div>

      <div class="grid gap-4 sm:grid-cols-2">
        <TeamCard
          v-for="team in teams.slice(0, 4)"
          :key="team.extid"
          :team="team"
          @click="navigateToTeam(team.extid)"
          @create-secret="handleCreateSecret" />
      </div>
    </div>

    <!-- Space divider -->
    <div class="mb-6"></div>

    <RecentSecretsTable v-if="isBetaEnabled" />
  </div>
</template>
