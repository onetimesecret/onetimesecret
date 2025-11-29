<!-- src/views/dashboard/SingleTeamDashboard.vue -->
<!-- Focused dashboard for users with exactly one team -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import SecretForm from '@/components/secrets/form/SecretForm.vue';
  import RecentSecretsTable from '@/components/secrets/RecentSecretsTable.vue';
  import { WindowService } from '@/services/window.service';
  import { useTeamStore } from '@/stores/teamStore';
  import { storeToRefs } from 'pinia';
  import { computed } from 'vue';
  import { useRouter } from 'vue-router';

  const { t } = useI18n();
  const router = useRouter();
  const teamStore = useTeamStore();
  const cust = WindowService.get('cust');

  const { teams } = storeToRefs(teamStore);

  const isBetaEnabled = computed(() => cust?.feature_flags?.beta ?? false);

  // Get the single team
  const team = computed(() => teams.value[0] ?? null);

  const navigateToTeam = () => {
    if (team.value) {
      router.push({ name: 'Teams Dashboard', params: { extid: team.value.extid } });
    }
  };

  const navigateToMembers = () => {
    if (team.value) {
      router.push({ name: 'Team Members', params: { extid: team.value.extid } });
    }
  };

  const navigateToSettings = () => {
    if (team.value) {
      router.push({ name: 'Team Settings', params: { extid: team.value.extid } });
    }
  };
</script>

<template>
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <SecretForm
      class="mb-12"
      :with-generate="true"
      :with-recipient="true" />

    <!-- Team Quick Access Card -->
    <div
      v-if="team"
      class="mb-12 overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
      <!-- Team Header -->
      <div class="border-b border-gray-200 bg-gray-50 px-6 py-4 dark:border-gray-700 dark:bg-gray-800/50">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class="flex size-10 items-center justify-center rounded-lg bg-brand-100 dark:bg-brand-900/30">
              <OIcon
                collection="heroicons"
                name="user-group"
                class="size-5 text-brand-600 dark:text-brand-400"
                aria-hidden="true" />
            </div>
            <div>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                {{ team.display_name }}
              </h2>
              <p
                v-if="team.description"
                class="text-sm text-gray-500 dark:text-gray-400">
                {{ team.description }}
              </p>
            </div>
          </div>

          <button
            type="button"
            @click="navigateToTeam"
            class="inline-flex items-center gap-1.5 text-sm font-medium text-brand-600 hover:text-brand-700 dark:text-brand-400 dark:hover:text-brand-300">
            {{ t('web.teams.view_dashboard') }}
            <OIcon
              collection="heroicons"
              name="arrow-right"
              class="size-4"
              aria-hidden="true" />
          </button>
        </div>
      </div>

      <!-- Quick Actions -->
      <div class="grid grid-cols-2 divide-x divide-gray-200 dark:divide-gray-700">
        <button
          type="button"
          @click="navigateToMembers"
          class="flex items-center justify-center gap-2 px-4 py-3 text-sm font-medium text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-gray-700/50">
          <OIcon
            collection="heroicons"
            name="users"
            class="size-5 text-gray-400"
            aria-hidden="true" />
          {{ t('web.teams.members') }}
          <span
            v-if="team.member_count"
            class="rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-600 dark:bg-gray-700 dark:text-gray-400">
            {{ team.member_count }}
          </span>
        </button>

        <button
          type="button"
          @click="navigateToSettings"
          class="flex items-center justify-center gap-2 px-4 py-3 text-sm font-medium text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-gray-700/50">
          <OIcon
            collection="heroicons"
            name="cog-6-tooth-solid"
            class="size-5 text-gray-400"
            aria-hidden="true" />
          {{ t('web.teams.settings') }}
        </button>
      </div>
    </div>

    <RecentSecretsTable v-if="isBetaEnabled" />
  </div>
</template>
