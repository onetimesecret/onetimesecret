<!-- src/views/teams/TeamView.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import SecretForm from '@/apps/secret/components/form/SecretForm.vue';
  import { useAsyncHandler } from '@/shared/composables/useAsyncHandler';
  import { getRoleBadgeColor, getRoleLabel } from '@/schemas/models/team';
  import { useTeamStore } from '@/shared/stores/teamStore';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useRoute, useRouter } from 'vue-router';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const route = useRoute();
  const router = useRouter();
  const teamStore = useTeamStore();

  const { activeTeam, loading } = storeToRefs(teamStore);

  const { wrap } = useAsyncHandler({
    notify: false, // Using local error state instead of notifications
  });

  const activeTab = ref<'overview' | 'members' | 'settings'>('overview');
  const error = ref('');
  const showCreateSecret = ref(false);

  const teamId = computed(() => route.params.extid as string);

  onMounted(async () => {
    const result = await wrap(() => teamStore.fetchTeam(teamId.value));
    if (!result) {
      error.value = t('web.teams.fetch_team_error');
    }

    // Check if we should auto-open the create secret form
    if (route.hash === '#create-secret') {
      showCreateSecret.value = true;
    }
  });

  const navigateToMembers = () => {
    router.push({ name: 'Team Members', params: { extid: teamId.value } });
  };

  const navigateToSettings = () => {
    router.push({ name: 'Team Settings', params: { extid: teamId.value } });
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
    <div
      v-if="error"
      class="mb-6 rounded-md bg-red-50 p-4 dark:bg-red-900/20">
      <div class="flex">
        <OIcon
          collection="heroicons"
          name="exclamation-circle"
          class="size-5 text-red-400 dark:text-red-300"
          aria-hidden="true" />
        <div class="ml-3">
          <p class="text-sm text-red-800 dark:text-red-400">
            {{ error }}
          </p>
        </div>
      </div>
    </div>

    <!-- Loading State -->
    <div
      v-if="loading && !activeTeam"
      class="space-y-4">
      <div class="h-16 animate-pulse rounded-lg bg-gray-200 dark:bg-gray-700"></div>
      <div class="h-96 animate-pulse rounded-lg bg-gray-200 dark:bg-gray-700"></div>
    </div>

    <!-- Content -->
    <div
      v-else-if="activeTeam"
      class="space-y-6">
      <!-- Header -->
      <div class="flex items-start justify-between">
        <div class="min-w-0 flex-1">
          <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
            {{ activeTeam.display_name }}
          </h1>
          <p
            v-if="activeTeam.description"
            class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            {{ activeTeam.description }}
          </p>
          <div class="mt-3 flex items-center gap-3">
            <span
              :class="[
                'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium',
                getRoleBadge.color,
              ]">
              {{ getRoleBadge.label }}
            </span>
            <div class="flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400">
              <OIcon
                collection="heroicons"
                name="users"
                class="size-4"
                aria-hidden="true" />
              <span>{{ activeTeam.member_count }}
                {{
                  activeTeam.member_count === 1 ? t('web.teams.member') : t('web.teams.members')
                }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Tabs -->
      <div class="border-b border-gray-200 dark:border-gray-700">
        <nav
          class="-mb-px flex space-x-8"
          aria-label="Tabs">
          <button
            @click="activeTab = 'overview'"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium transition-colors',
              activeTab === 'overview'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            <div class="flex items-center gap-2">
              <OIcon
                collection="heroicons"
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
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            <div class="flex items-center gap-2">
              <OIcon
                collection="heroicons"
                name="users"
                class="size-5"
                aria-hidden="true" />
              <span>{{ t('web.teams.members') }}</span>
              <span
                class="ml-2 rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-700 dark:text-gray-400">
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
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            <div class="flex items-center gap-2">
              <OIcon
                collection="heroicons"
                name="cog-6-tooth-solid"
                class="size-5"
                aria-hidden="true" />
              <span>{{ t('web.teams.settings') }}</span>
            </div>
          </button>
        </nav>
      </div>

      <!-- Overview Tab -->
      <div
        v-if="activeTab === 'overview'"
        class="space-y-6">
        <!-- Create Team Secret Section -->
        <div
          class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <div class="mb-4 flex items-start justify-between">
            <div>
              <h2 class="text-lg font-medium text-gray-900 dark:text-white">
                {{ t('web.teams.create_team_secret') }}
              </h2>
              <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
                {{ t('web.teams.create_team_secret_description') }}
              </p>
            </div>
            <button
              v-if="showCreateSecret"
              type="button"
              @click="showCreateSecret = false"
              class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
              :aria-label="t('web.teams.close_secret_form')">
              <OIcon
                collection="heroicons"
                name="x-mark"
                class="size-5"
                aria-hidden="true" />
            </button>
          </div>

          <div v-if="!showCreateSecret">
            <button
              type="button"
              @click="showCreateSecret = true"
              class="inline-flex items-center gap-2 rounded-lg bg-brand-600 px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:bg-brand-500 dark:hover:bg-brand-600">
              <OIcon
                collection="heroicons"
                name="plus"
                class="size-5"
                aria-hidden="true" />
              {{ t('web.teams.new_team_secret') }}
            </button>
          </div>

          <div
            v-else
            class="mt-4">
            <SecretForm
              :with-generate="false"
              :with-recipient="false"
              :with-expiry="true" />
          </div>
        </div>

        <!-- Quick Actions -->
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <button
            type="button"
            @click="navigateToMembers"
            class="group relative rounded-lg border border-gray-200 bg-white p-6 text-left shadow-sm transition-all hover:border-brand-500 hover:shadow-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-700 dark:bg-gray-800 dark:hover:border-brand-400">
            <div class="flex items-center gap-4">
              <div
                class="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900">
                <OIcon
                  collection="heroicons"
                  name="users"
                  class="size-6 text-brand-600 dark:text-brand-400"
                  aria-hidden="true" />
              </div>
              <div class="min-w-0 flex-1">
                <h3
                  class="text-sm font-medium text-gray-900 group-hover:text-brand-600 dark:text-white dark:group-hover:text-brand-400">
                  {{ t('web.teams.manage_members') }}
                </h3>
                <p class="text-sm text-gray-500 dark:text-gray-400">
                  {{ activeTeam.member_count }}
                  {{
                    activeTeam.member_count === 1 ? t('web.teams.member') : t('web.teams.members')
                  }}
                </p>
              </div>
            </div>
          </button>

          <button
            v-if="activeTeam.current_user_role === 'owner'"
            type="button"
            @click="navigateToSettings"
            class="group relative rounded-lg border border-gray-200 bg-white p-6 text-left shadow-sm transition-all hover:border-brand-500 hover:shadow-md focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2 dark:border-gray-700 dark:bg-gray-800 dark:hover:border-brand-400">
            <div class="flex items-center gap-4">
              <div
                class="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-100 dark:bg-brand-900">
                <OIcon
                  collection="heroicons"
                  name="cog-6-tooth-solid"
                  class="size-6 text-brand-600 dark:text-brand-400"
                  aria-hidden="true" />
              </div>
              <div class="min-w-0 flex-1">
                <h3
                  class="text-sm font-medium text-gray-900 group-hover:text-brand-600 dark:text-white dark:group-hover:text-brand-400">
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
        <div
          class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800">
          <h2 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.teams.team_information') }}
          </h2>
          <dl class="mt-4 space-y-3">
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                {{ t('web.teams.created') }}
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {{ activeTeam.created.toLocaleDateString() }}
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-gray-400">
                {{ t('web.teams.last_updated') }}
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {{ activeTeam.updated.toLocaleDateString() }}
              </dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
  </div>
</template>
