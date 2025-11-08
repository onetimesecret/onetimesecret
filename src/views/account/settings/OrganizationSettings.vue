<!-- src/views/account/settings/OrganizationSettings.vue -->

<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import SettingsLayout from '@/components/layout/SettingsLayout.vue';
import OIcon from '@/components/icons/OIcon.vue';
import BasicFormAlerts from '@/components/BasicFormAlerts.vue';
import { useOrganizationStore } from '@/stores/organizationStore';
import { useTeamStore } from '@/stores/teamStore';
import { classifyError } from '@/schemas/errors';
import type { Organization } from '@/types/organization';
import type { Team } from '@/types/team';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const organizationStore = useOrganizationStore();
const teamStore = useTeamStore();

const orgId = computed(() => route.params.orgid as string);
const organization = ref<Organization | null>(null);
const teams = ref<Team[]>([]);
const activeTab = ref<'general' | 'teams' | 'billing'>('general');

const isLoading = ref(false);
const isSaving = ref(false);
const error = ref('');
const success = ref('');

// Form data
const formData = ref({
  display_name: '',
  description: '',
  contact_email: '',
});

const isDirty = computed(() => {
  if (!organization.value) return false;
  return (
    formData.value.display_name !== organization.value.display_name ||
    formData.value.description !== (organization.value.description || '') ||
    formData.value.contact_email !== (organization.value.contact_email || '')
  );
});

const loadOrganization = async () => {
  isLoading.value = true;
  error.value = '';
  try {
    const org = await organizationStore.fetchOrganization(orgId.value);
    if (org) {
      organization.value = org;
      formData.value = {
        display_name: org.display_name,
        description: org.description || '',
        contact_email: org.contact_email || '',
      };
    } else {
      error.value = t('web.organizations.not_found');
    }
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.userMessage || t('web.organizations.load_error');
    console.error('[OrganizationSettings] Error loading organization:', err);
  } finally {
    isLoading.value = false;
  }
};

const loadTeams = async () => {
  try {
    // Load all teams and filter by org_id
    await teamStore.fetchTeams();
    teams.value = teamStore.teams.filter(team => team.org_id === orgId.value);
  } catch (err) {
    console.error('[OrganizationSettings] Error loading teams:', err);
  }
};

const handleSave = async () => {
  if (!organization.value || !isDirty.value) return;

  isSaving.value = true;
  error.value = '';
  success.value = '';

  try {
    await organizationStore.updateOrganization(organization.value.id, {
      display_name: formData.value.display_name,
      description: formData.value.description,
      contact_email: formData.value.contact_email,
    });
    success.value = t('web.organizations.update_success');
    await loadOrganization(); // Reload to get latest data
  } catch (err) {
    const classified = classifyError(err);
    error.value = classified.userMessage || t('web.organizations.update_error');
    console.error('[OrganizationSettings] Error updating organization:', err);
  } finally {
    isSaving.value = false;
  }
};

const handleCancel = () => {
  if (organization.value) {
    formData.value = {
      display_name: organization.value.display_name,
      description: organization.value.description || '',
      contact_email: organization.value.contact_email || '',
    };
  }
};

const handleTeamClick = (team: Team) => {
  router.push(`/teams/${team.id}`);
};

onMounted(async () => {
  await loadOrganization();
  if (activeTab.value === 'teams') {
    await loadTeams();
  }
});

watch(activeTab, async (newTab) => {
  if (newTab === 'teams' && teams.value.length === 0) {
    await loadTeams();
  }
});
</script>

<template>
  <SettingsLayout>
    <div class="space-y-6">
      <!-- Breadcrumb -->
      <nav class="flex" aria-label="Breadcrumb">
        <ol class="flex items-center space-x-2">
          <li>
            <router-link
              to="/account/settings/organizations"
              class="text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-300">
              {{ t('web.organizations.title') }}
            </router-link>
          </li>
          <li>
            <OIcon
              collection="heroicons"
              name="chevron-right"
              class="size-4 text-gray-400"
              aria-hidden="true" />
          </li>
          <li class="text-sm font-medium text-gray-900 dark:text-white">
            {{ organization?.display_name || t('web.COMMON.loading') }}
          </li>
        </ol>
      </nav>

      <!-- Tabs -->
      <div class="border-b border-gray-200 dark:border-gray-700">
        <nav class="-mb-px flex space-x-8" aria-label="Tabs">
          <button
            @click="activeTab = 'general'"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'general'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ t('web.organizations.tabs.general') }}
          </button>
          <button
            @click="activeTab = 'teams'"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'teams'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ t('web.organizations.tabs.teams') }}
          </button>
          <button
            @click="activeTab = 'billing'"
            :class="[
              'whitespace-nowrap border-b-2 px-1 py-4 text-sm font-medium',
              activeTab === 'billing'
                ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
                : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
            ]">
            {{ t('web.organizations.tabs.billing') }}
          </button>
        </nav>
      </div>

      <!-- Loading State -->
      <div v-if="isLoading" class="flex items-center justify-center py-12">
        <div class="text-center">
          <OIcon
            collection="heroicons"
            name="arrow-path"
            class="mx-auto size-8 animate-spin text-gray-400"
            aria-hidden="true" />
          <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
            {{ t('web.COMMON.loading') }}
          </p>
        </div>
      </div>

      <!-- Content -->
      <div v-else>
        <!-- General Tab -->
        <section
          v-if="activeTab === 'general'"
          class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <h3 class="text-base font-semibold text-gray-900 dark:text-white">
              {{ t('web.organizations.general_settings') }}
            </h3>
          </div>

          <div class="p-6">
            <BasicFormAlerts
              v-if="error"
              :error="error" />
            <BasicFormAlerts
              v-if="success"
              :success="success" />

            <form @submit.prevent="handleSave" class="mt-4 space-y-6">
              <!-- Display Name -->
              <div>
                <label
                  for="display-name"
                  class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ t('web.organizations.display_name') }}
                  <span class="text-red-500">*</span>
                </label>
                <input
                  id="display-name"
                  v-model="formData.display_name"
                  type="text"
                  required
                  maxlength="100"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-400" />
              </div>

              <!-- Description -->
              <div>
                <label
                  for="description"
                  class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ t('web.organizations.description') }}
                </label>
                <textarea
                  id="description"
                  v-model="formData.description"
                  rows="3"
                  maxlength="500"
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-400"></textarea>
                <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                  {{ formData.description.length }}/500
                </p>
              </div>

              <!-- Contact Email -->
              <div>
                <label
                  for="contact-email"
                  class="block text-sm font-medium text-gray-700 dark:text-gray-300">
                  {{ t('web.organizations.contact_email') }}
                  <span class="text-red-500">*</span>
                </label>
                <input
                  id="contact-email"
                  v-model="formData.contact_email"
                  type="email"
                  required
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-brand-500 focus:ring-brand-500 sm:text-sm dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder-gray-400" />
                <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
                  {{ t('web.organizations.contact_email_help') }}
                </p>
              </div>

              <!-- Action Buttons -->
              <div class="flex items-center justify-end gap-3">
                <button
                  v-if="isDirty"
                  type="button"
                  @click="handleCancel"
                  :disabled="isSaving"
                  class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-gray-700 dark:text-gray-100 dark:ring-gray-600 dark:hover:bg-gray-600">
                  {{ t('web.COMMON.word_cancel') }}
                </button>
                <button
                  type="submit"
                  :disabled="!isDirty || isSaving"
                  class="rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-brand-500 dark:hover:bg-brand-400">
                  <span v-if="!isSaving">{{ t('web.COMMON.save_changes') }}</span>
                  <span v-else>{{ t('web.COMMON.saving') }}</span>
                </button>
              </div>
            </form>
          </div>
        </section>

        <!-- Teams Tab -->
        <section
          v-if="activeTab === 'teams'"
          class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <div class="flex items-center justify-between">
              <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                {{ t('web.organizations.teams_in_organization') }}
              </h3>
              <router-link
                to="/teams/new"
                class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 dark:bg-brand-500 dark:hover:bg-brand-400">
                <OIcon
                  collection="heroicons"
                  name="plus"
                  class="size-4"
                  aria-hidden="true" />
                {{ t('web.teams.create_team') }}
              </router-link>
            </div>
          </div>

          <div class="p-6">
            <div v-if="teams.length > 0" class="space-y-3">
              <div
                v-for="team in teams"
                :key="team.id"
                @click="handleTeamClick(team)"
                class="flex cursor-pointer items-center justify-between rounded-lg border border-gray-200 p-4 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700/50">
                <div>
                  <h4 class="text-base font-medium text-gray-900 dark:text-white">
                    {{ team.display_name }}
                  </h4>
                  <p class="text-sm text-gray-500 dark:text-gray-400">
                    {{ team.member_count }} {{ t('web.teams.members') }}
                  </p>
                </div>
                <OIcon
                  collection="heroicons"
                  name="chevron-right"
                  class="size-5 text-gray-400"
                  aria-hidden="true" />
              </div>
            </div>
            <div v-else class="py-12 text-center">
              <OIcon
                collection="heroicons"
                name="user-group"
                class="mx-auto size-12 text-gray-400"
                aria-hidden="true" />
              <p class="mt-2 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.no_teams') }}
              </p>
            </div>
          </div>
        </section>

        <!-- Billing Tab -->
        <section
          v-if="activeTab === 'billing'"
          class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
          <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
            <h3 class="text-base font-semibold text-gray-900 dark:text-white">
              {{ t('web.organizations.billing_settings') }}
            </h3>
          </div>

          <div class="p-6">
            <div class="rounded-lg border-2 border-dashed border-gray-300 p-12 text-center dark:border-gray-600">
              <OIcon
                collection="heroicons"
                name="credit-card"
                class="mx-auto size-12 text-gray-400"
                aria-hidden="true" />
              <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
                {{ t('web.organizations.billing_coming_soon') }}
              </h3>
              <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                {{ t('web.organizations.billing_coming_soon_description') }}
              </p>
            </div>
          </div>
        </section>
      </div>
    </div>
  </SettingsLayout>
</template>
