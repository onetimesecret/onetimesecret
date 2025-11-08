<!-- src/views/teams/TeamSettings.vue -->
<script setup lang="ts">
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import ConfirmDialog from '@/components/ConfirmDialog.vue';
import OIcon from '@/components/icons/OIcon.vue';
import { classifyError } from '@/schemas/errors';
import { useTeamStore } from '@/stores/teamStore';
import { updateTeamPayloadSchema, type UpdateTeamPayload } from '@/types/team';
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { storeToRefs } from 'pinia';
import { z } from 'zod';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const teamStore = useTeamStore();

const { activeTeam, loading } = storeToRefs(teamStore);

const formData = ref<UpdateTeamPayload>({
  name: '',
  description: '',
});
const errors = ref<Record<string, string>>({});
const generalError = ref('');
const successMessage = ref('');
const isSubmitting = ref(false);
const showDeleteConfirm = ref(false);
const isDeleting = ref(false);

const teamId = computed(() => route.params.teamid as string);

const isOwner = computed(() => activeTeam.value?.current_user_role === 'owner');

const isFormDirty = computed(() => {
  if (!activeTeam.value) return false;
  return (
    formData.value.name !== activeTeam.value.name ||
    formData.value.description !== (activeTeam.value.description || '')
  );
});

onMounted(async () => {
  if (!isOwner.value) {
    router.push({ name: 'Team Dashboard', params: { teamid: teamId.value } });
    return;
  }

  try {
    if (!activeTeam.value || activeTeam.value.id !== teamId.value) {
      await teamStore.fetchTeam(teamId.value);
    }
  } catch (err) {
    const classified = classifyError(err);
    generalError.value = classified.userMessage || t('web.teams.fetch_team_error');
  }
});

watch(
  activeTeam,
  (team) => {
    if (team) {
      formData.value = {
        name: team.name,
        description: team.description || '',
      };
    }
  },
  { immediate: true }
);

const handleSubmit = async () => {
  if (!isFormDirty.value || isSubmitting.value || !isOwner.value) return;

  errors.value = {};
  generalError.value = '';
  successMessage.value = '';
  isSubmitting.value = true;

  try {
    updateTeamPayloadSchema.parse(formData.value);

    await teamStore.updateTeam(teamId.value, formData.value);

    successMessage.value = t('web.teams.update_success');
  } catch (err) {
    if (err instanceof z.ZodError) {
      err.errors.forEach((error) => {
        const field = error.path[0] as string;
        errors.value[field] = error.message;
      });
    } else {
      const classified = classifyError(err);
      generalError.value = classified.userMessage || t('web.teams.update_error');
    }
  } finally {
    isSubmitting.value = false;
  }
};

const handleDeleteTeam = async () => {
  showDeleteConfirm.value = false;

  if (!isOwner.value || isDeleting.value) return;

  isDeleting.value = true;

  try {
    await teamStore.deleteTeam(teamId.value);
    router.push({ name: 'Teams' });
  } catch (err) {
    const classified = classifyError(err);
    generalError.value = classified.userMessage || t('web.teams.delete_error');
    isDeleting.value = false;
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
            {{ t('web.teams.settings') }}
          </span>
        </li>
      </ol>
    </nav>

    <!-- Header -->
    <div class="mb-8">
      <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
        {{ t('web.teams.team_settings') }}
      </h1>
      <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
        {{ t('web.teams.team_settings_description') }}
      </p>
    </div>

    <!-- Loading State -->
    <div v-if="loading && !activeTeam" class="space-y-4">
      <div class="h-96 animate-pulse rounded-lg bg-gray-200 dark:bg-gray-700"></div>
    </div>

    <!-- Settings Form -->
    <div v-else-if="activeTeam && isOwner" class="space-y-6">
      <!-- General Settings -->
      <div class="rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <h2 class="text-lg font-medium text-gray-900 dark:text-white">
            {{ t('web.teams.general_settings') }}
          </h2>
        </div>

        <form @submit.prevent="handleSubmit" class="p-6">
          <BasicFormAlerts v-if="generalError" :error="generalError" />
          <BasicFormAlerts v-if="successMessage" :success="successMessage" />

          <div class="space-y-6">
            <!-- Team Name -->
            <div>
              <label for="team-name" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.teams.team_name') }}
                <span class="text-red-500">*</span>
              </label>
              <input
                id="team-name"
                v-model="formData.name"
                type="text"
                required
                maxlength="100"
                :placeholder="t('web.teams.team_name_placeholder')"
                :class="[
                  'mt-1 block w-full rounded-md shadow-sm sm:text-sm',
                  'focus:ring-brand-500 focus:border-brand-500',
                  'dark:bg-gray-700 dark:border-gray-600 dark:text-white dark:placeholder-gray-400',
                  errors.name
                    ? 'border-red-300 text-red-900 placeholder-red-300 focus:border-red-500 focus:ring-red-500'
                    : 'border-gray-300 dark:border-gray-600'
                ]"
              />
              <p v-if="errors.name" class="mt-1 text-sm text-red-600 dark:text-red-400">
                {{ errors.name }}
              </p>
            </div>

            <!-- Description -->
            <div>
              <label for="team-description" class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ t('web.teams.description') }}
              </label>
              <textarea
                id="team-description"
                v-model="formData.description"
                rows="3"
                maxlength="500"
                :placeholder="t('web.teams.description_placeholder')"
                :class="[
                  'mt-1 block w-full rounded-md shadow-sm sm:text-sm',
                  'focus:ring-brand-500 focus:border-brand-500',
                  'dark:bg-gray-700 dark:border-gray-600 dark:text-white dark:placeholder-gray-400',
                  errors.description
                    ? 'border-red-300 text-red-900 placeholder-red-300 focus:border-red-500 focus:ring-red-500'
                    : 'border-gray-300 dark:border-gray-600'
                ]"
              ></textarea>
              <p v-if="errors.description" class="mt-1 text-sm text-red-600 dark:text-red-400">
                {{ errors.description }}
              </p>
              <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                {{ formData.description?.length || 0 }}/500
              </p>
            </div>
          </div>

          <div class="mt-6 flex justify-end">
            <button
              type="submit"
              :disabled="!isFormDirty || isSubmitting"
              class="inline-flex items-center rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400"
            >
              <span v-if="!isSubmitting">{{ t('web.teams.save_changes') }}</span>
              <span v-else>{{ t('web.COMMON.processing') }}</span>
            </button>
          </div>
        </form>
      </div>

      <!-- Danger Zone -->
      <div class="rounded-lg border border-red-200 bg-white shadow-sm dark:border-red-900 dark:bg-gray-800">
        <div class="border-b border-red-200 px-6 py-4 dark:border-red-900">
          <h2 class="text-lg font-medium text-red-900 dark:text-red-400">
            {{ t('web.teams.danger_zone') }}
          </h2>
        </div>

        <div class="p-6">
          <div class="flex items-start justify-between">
            <div class="flex-1">
              <h3 class="text-sm font-medium text-gray-900 dark:text-white">
                {{ t('web.teams.delete_team') }}
              </h3>
              <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {{ activeTeam?.is_default ? t('web.teams.delete_default_team_warning') : t('web.teams.delete_team_warning') }}
              </p>
            </div>
            <button
              type="button"
              @click="showDeleteConfirm = true"
              :disabled="isDeleting || activeTeam?.is_default"
              class="ml-4 inline-flex items-center rounded-md bg-red-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-red-700 dark:hover:bg-red-600"
            >
              <OIcon collection="heroicons"
name="trash"
class="-ml-0.5 mr-1.5 size-5"
aria-hidden="true" />
              {{ t('web.teams.delete') }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Delete Confirmation Dialog -->
    <ConfirmDialog
      v-if="showDeleteConfirm"
      :title="t('web.teams.delete_team_confirm_title')"
      :message="t('web.teams.delete_team_confirm_message', { name: activeTeam?.display_name })"
      :confirm-text="t('web.teams.delete')"
      :cancel-text="t('web.COMMON.word_cancel')"
      type="danger"
      @confirm="handleDeleteTeam"
      @cancel="showDeleteConfirm = false"
    />
  </div>
</template>
