<!-- src/views/teams/TeamMembers.vue -->

<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import OIcon from '@/components/icons/OIcon.vue';
import TeamMembersList from '@/components/teams/TeamMembersList.vue';
import { classifyError } from '@/schemas/errors';
import { useTeamStore } from '@/stores/teamStore';
import { inviteMemberPayloadSchema, TeamRole, type InviteMemberPayload } from '@/types/team';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { storeToRefs } from 'pinia';
import { z } from 'zod';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const teamStore = useTeamStore();

const { activeTeam, members, loading } = storeToRefs(teamStore);

const showInviteForm = ref(false);
const inviteFormData = ref<InviteMemberPayload>({
  email: '',
  role: TeamRole.MEMBER,
});
const inviteErrors = ref<Record<string, string>>({});
const inviteGeneralError = ref('');
const isInviting = ref(false);
const error = ref('');

const teamId = computed(() => route.params.teamid as string);

const canManageMembers = computed(() => {
  if (!activeTeam.value) return false;
  return activeTeam.value.current_user_role === TeamRole.OWNER || activeTeam.value.current_user_role === TeamRole.ADMIN;
});

// Get current user ID from window state
const currentUserId = computed(() => window.__ONETIME_STATE__?.customer?.custid);

onMounted(async () => {
  try {
    if (!activeTeam.value || activeTeam.value.id !== teamId.value) {
      await teamStore.fetchTeam(teamId.value);
    }
    await teamStore.fetchMembers(teamId.value);
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.userMessage || t('web.teams.fetch_members_error');
  }
});

const handleInviteMember = async () => {
  if (!canManageMembers.value || isInviting.value) return;

  inviteErrors.value = {};
  inviteGeneralError.value = '';
  isInviting.value = true;

  try {
    inviteMemberPayloadSchema.parse(inviteFormData.value);

    await teamStore.inviteMember(teamId.value, inviteFormData.value);

    // Success - reset form
    inviteFormData.value = {
      email: '',
      role: TeamRole.MEMBER,
    };
    showInviteForm.value = false;
  } catch (err) {
    if (err instanceof z.ZodError) {
      err.errors.forEach((error) => {
        const field = error.path[0] as string;
        inviteErrors.value[field] = error.message;
      });
    } else {
      const classified = classifyError(err);
      inviteGeneralError.value = classified.userMessage || t('web.teams.invite_error');
    }
  } finally {
    isInviting.value = false;
  }
};

const navigateToTeam = () => {
  router.push({ name: 'Team Dashboard', params: { teamid: teamId.value } });
};
</script>

<template>
  <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
    <!-- Breadcrumb -->
    <nav class="mb-4 flex" aria-label="Breadcrumb">
      <ol class="flex items-center space-x-2">
        <li>
          <router-link
            :to="{ name: 'Teams' }"
            class="text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300"
          >
            {{ t('web.teams.teams') }}
          </router-link>
        </li>
        <li>
          <OIcon collection="heroicons"
name="chevron-right"
class="size-4 text-gray-400"
aria-hidden="true" />
        </li>
        <li>
          <button
            @click="navigateToTeam"
            class="text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300"
          >
            {{ activeTeam?.display_name }}
          </button>
        </li>
        <li>
          <OIcon collection="heroicons"
name="chevron-right"
class="size-4 text-gray-400"
aria-hidden="true" />
        </li>
        <li>
          <span class="text-sm font-medium text-gray-900 dark:text-white">
            {{ t('web.teams.members') }}
          </span>
        </li>
      </ol>
    </nav>

    <!-- Header -->
    <div class="mb-8 flex items-center justify-between">
      <div>
        <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
          {{ t('web.teams.team_members') }}
        </h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.teams.team_members_description') }}
        </p>
      </div>

      <button
        v-if="canManageMembers"
        type="button"
        @click="showInviteForm = !showInviteForm"
        class="inline-flex items-center rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400"
      >
        <OIcon collection="heroicons"
name="user-plus"
class="-ml-0.5 mr-1.5 size-5"
aria-hidden="true" />
        {{ t('web.teams.invite_member') }}
      </button>
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

    <!-- Invite Form -->
    <div
      v-if="showInviteForm"
      class="mb-6 rounded-lg border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-800"
    >
      <h2 class="text-lg font-medium text-gray-900 dark:text-white">
        {{ t('web.teams.invite_new_member') }}
      </h2>

      <form @submit.prevent="handleInviteMember" class="mt-4 space-y-4">
        <BasicFormAlerts v-if="inviteGeneralError" :error="inviteGeneralError" />

        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label for="invite-email" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.teams.email_address') }}
              <span class="text-red-500">*</span>
            </label>
            <input
              id="invite-email"
              v-model="inviteFormData.email"
              type="email"
              required
              :placeholder="t('web.teams.email_placeholder')"
              :class="[
                'mt-1 block w-full rounded-md shadow-sm sm:text-sm',
                'focus:ring-brand-500 focus:border-brand-500',
                'dark:bg-gray-700 dark:border-gray-600 dark:text-white dark:placeholder-gray-400',
                inviteErrors.email
                  ? 'border-red-300 text-red-900 placeholder-red-300 focus:border-red-500 focus:ring-red-500'
                  : 'border-gray-300 dark:border-gray-600'
              ]"
            />
            <p v-if="inviteErrors.email" class="mt-1 text-sm text-red-600 dark:text-red-400">
              {{ inviteErrors.email }}
            </p>
          </div>

          <div>
            <label for="invite-role" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.teams.role') }}
            </label>
            <select
              id="invite-role"
              v-model="inviteFormData.role"
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white sm:text-sm"
            >
              <option :value="TeamRole.MEMBER">{{ t('web.teams.roles.member') }}</option>
              <option v-if="activeTeam?.current_user_role === TeamRole.OWNER" :value="TeamRole.ADMIN">
                {{ t('web.teams.roles.admin') }}
              </option>
            </select>
          </div>
        </div>

        <div class="flex justify-end gap-3">
          <button
            type="button"
            @click="showInviteForm = false"
            :disabled="isInviting"
            class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600"
          >
            {{ t('web.COMMON.word_cancel') }}
          </button>
          <button
            type="submit"
            :disabled="isInviting || !inviteFormData.email"
            class="inline-flex items-center rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400"
          >
            <span v-if="!isInviting">{{ t('web.teams.send_invite') }}</span>
            <span v-else>{{ t('web.COMMON.processing') }}</span>
          </button>
        </div>
      </form>
    </div>

    <!-- Loading State -->
    <div v-if="loading && members.length === 0" class="rounded-lg border border-gray-200 bg-white p-6 dark:border-gray-700 dark:bg-gray-800">
      <div class="animate-pulse space-y-4">
        <div class="h-10 rounded bg-gray-200 dark:bg-gray-700"></div>
        <div class="h-10 rounded bg-gray-200 dark:bg-gray-700"></div>
        <div class="h-10 rounded bg-gray-200 dark:bg-gray-700"></div>
      </div>
    </div>

    <!-- Members List -->
    <TeamMembersList
      v-else-if="activeTeam"
      :team="activeTeam"
      :members="members"
      :current-user-id="currentUserId"
      @member-removed="() => {}"
      @role-changed="() => {}"
    />
  </div>
</template>
