<!-- src/views/teams/TeamDashboard.vue -->

<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { classifyError } from '@/schemas/errors';
import { useTeamStore } from '@/stores/teamStore';
import { getRoleBadgeColor, getRoleLabel } from '@/types/team';
import { onMounted, ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { storeToRefs } from 'pinia';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const teamStore = useTeamStore();

const { activeTeam, loading } = storeToRefs(teamStore);

const activeTab = ref<'overview' | 'members' | 'settings'>('overview');
const error = ref('');

const teamId = computed(() => route.params.teamid as string);

onMounted(async () => {
  try {
    await teamStore.fetchTeam(teamId.value);
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.userMessage || t('web.teams.fetch_team_error');
  }
});

const navigateToMembers = () => {
  router.push({ name: 'Team Members', params: { teamid: teamId.value } });
};

const navigateToSettings = () => {
  router.push({ name: 'Team Settings', params: { teamid: teamId.value } });
};

const getRoleBadge = computed(() => {
  if (!activeTeam.value) return { color: '', label: '' };
  return {
    color: getRoleBadgeColor(activeTeam.value.current_user_role),
    label: t(getRoleLabel(activeTeam.value.current_user_role)),
  };
});
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
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

    <!-- Loading State -->
    <div v-if="loading && !activeTeam" class="space-y-4">
      <div class="h-16 animate-pulse rounded-lg bg-gray-200 dark:bg-gray-700"></div>
      <div class="h-96 animate-pulse rounded-lg bg-gray-200 dark:bg-gray-700"></div>
    </div>

    <!-- Content -->
    <div v-else-if="activeTeam" class="space-y-6">
      <!-- Header -->
      <div class="flex items-start justify-between">
        <div class="min-w-0 flex-1">
          <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
            {{ activeTeam.display_name }}
          </h1>
          <p v-if="activeTeam.description" class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            {{ activeTeam.description }}
          </p>
          <div class="mt-3 flex items-center gap-3">
            <span
              :class="[
                'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
                getRoleBadge.color
              ]"
            >
              {{ getRoleBadge.label }}
            </span>
            <div class="flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400">
              <OIcon collection="heroicons"
name="users"
class="size-4"
aria-hidden="true" />
              <span>{{ activeTeam.member_count }} {{ activeTeam.member_count === 1 ? t('web.teams.member') : t('web.teams.members') }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Tabs -->
      <div class="border-b border-gray-200 dark:border-gray-700">
        <nav class="-mb-px flex space-x-8" aria-label="Tabs">
          <button
            @click="activeTab = 'overview'"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium transition-colors',
              activeTab === 'overview'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300'
            ]"
          >
            <div class="flex items-center gap-2">
              <OIcon collection="heroicons"
name="home"
class="size-5"
aria-hidden="true" />
              <span>{{ t('web.teams.overview') }}</span>
            </div>
          </button>
          <button
            @click="navigateToMembers"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium transition-colors',
              activeTab === 'members'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300'
            ]"
          >
            <div class="flex items-center gap-2">
              <OIcon collection="heroicons"
name="users"
class="size-5"
aria-hidden="true" />
              <span>{{ t('web.teams.members') }}</span>
              <span
                class="ml-2 rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-700 dark:text-gray-400"
              >
                {{ activeTeam.member_count }}
              </span>
            </div>
          </button>
          <button
            v-if="activeTeam.current_user_role === 'owner'"
            @click="navigateToSettings"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium transition-colors',
              activeTab === 'settings'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300'
            ]"
          >
            <div class="flex items-center gap-2">
              <OIcon collection="heroicons"
name="cog-6-tooth"
class="size-5"
aria-hidden="true" />
              <span>{{ t('web.teams.settings') }}</span>
            </div>
          </button>
        </nav>
      </div>

      <!-- Overview Tab -->
      <div v-if="activeTab === 'overview'" class="space-y-6">
        <!-- Quick Actions -->
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <button
            type="button"
            @click="navigateToMembers"
            class="group relative rounded-lg border border-gray-200 bg-white p-6 text-left shadow-sm transition-all hover:border-brand-500 hover:shadow-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-700 dark:bg-gray-800 dark:hover:border-brand-400"
          >
            <div class="flex items-center gap-4">
              <div class="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900">
                <OIcon
                  collection="heroicons"
                  name="users"
                  class="size-6 text-brand-600 dark:text-brand-400"
                  aria-hidden="true"
                />
              </div>
              <div class="min-w-0 flex-1">
                <h3 class="text-sm font-medium text-gray-900 group-hover:text-brand-600 dark:text-white dark:group-hover:text-brand-400">
                  {{ t('web.teams.manage_members') }}
                </h3>
                <p class="text-sm text-gray-500 dark:text-gray-400">
                  {{ activeTeam.member_count }} {{ activeTeam.member_count === 1 ? t('web.teams.member') : t('web.teams.members') }}
                </p>
              </div>
            </div>
          </button>

          <button
            v-if="activeTeam.current_user_role === 'owner'"
            type="button"
            @click="navigateToSettings"
            class="group relative rounded-lg border border-gray-200 bg-white p-6 text-left shadow-sm transition-all hover:border-brand-500 hover:shadow-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-700 dark:bg-gray-800 dark:hover:border-brand-400"
          >
            <div class="flex items-center gap-4">
              <div class="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900">
                <OIcon
                  collection="heroicons"
                  name="cog-6-tooth"
                  class="size-6 text-brand-600 dark:text-brand-400"
                  aria-hidden="true"
                />
              </div>
              <div class="min-w-0 flex-1">
                <h3 class="text-sm font-medium text-gray-900 group-hover:text-brand-600 dark:text-white dark:group-hover:text-brand-400">
                  {{ t('web.teams.team_settings') }}
                </h3>
                <p class="text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.teams.configure_team') }}
                </p>
              </div>
            </div>
          </button>
        </div>

        <!-- Team Info -->
        <div class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <h2 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.teams.team_information') }}
          </h2>
          <dl class="mt-4 space-y-3">
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                {{ t('web.teams.created') }}
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {{ new Date(activeTeam.created_at).toLocaleDateString() }}
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                {{ t('web.teams.last_updated') }}
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {{ new Date(activeTeam.updated_at).toLocaleDateString() }}
              </dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
  </div>
</template>
