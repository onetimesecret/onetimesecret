<!-- src/views/account/settings/OrganizationsSettings.vue -->

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import SettingsLayout from '@/components/layout/SettingsLayout.vue';
import OIcon from '@/components/icons/OIcon.vue';
import CreateOrganizationModal from '@/components/organizations/CreateOrganizationModal.vue';
import { useOrganizationStore } from '@/stores/organizationStore';
import type { Organization } from '@/types/organization';

const { t } = useI18n();
const router = useRouter();
const organizationStore = useOrganizationStore();

const isLoading = ref(false);
const showCreateModal = ref(false);

// Filter out default orgs for individual plan users (future plan-gating logic)
const visibleOrganizations = computed(() =>
  // For now, show all orgs. In future, filter by:
  // - User's plan (hide default org for individual plans)
  // - User's role (show only orgs where user is owner/admin)
   organizationStore.organizations
);

const hasOrganizations = computed(() => visibleOrganizations.value.length > 0);

onMounted(async () => {
  isLoading.value = true;
  try {
    await organizationStore.fetchOrganizations();
  } catch (error) {
    console.error('[OrganizationsSettings] Error fetching organizations:', error);
  } finally {
    isLoading.value = false;
  }
});

const handleCreateOrganization = () => {
  showCreateModal.value = true;
};

const handleOrganizationCreated = (orgId: string) => {
  showCreateModal.value = false;
  // Navigate to the new organization's settings
  router.push(`/account/settings/organization/${orgId}`);
};

const handleManageOrganization = (org: Organization) => {
  router.push(`/account/settings/organization/${org.id}`);
};
</script>

<template>
  <SettingsLayout>
    <div class="space-y-8">
      <!-- Organizations Section -->
      <section
        class="rounded-lg border border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
        <div class="border-b border-gray-200 px-6 py-4 dark:border-gray-700">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <OIcon
                collection="heroicons"
                name="building-office-2"
                class="size-5 text-gray-500 dark:text-gray-400"
                aria-hidden="true" />
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
                {{ t('web.organizations.title') }}
              </h2>
            </div>
            <button
              @click="handleCreateOrganization"
              class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400">
              <OIcon
                collection="heroicons"
                name="plus"
                class="size-4"
                aria-hidden="true" />
              {{ t('web.organizations.create_organization') }}
            </button>
          </div>
        </div>

        <div class="p-6">
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

          <!-- Organizations List -->
          <div v-else-if="hasOrganizations" class="space-y-4">
            <div
              v-for="org in visibleOrganizations"
              :key="org.id"
              class="flex items-center justify-between rounded-lg border border-gray-200 p-4 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700/50">
              <div class="flex-1">
                <h3 class="text-base font-medium text-gray-900 dark:text-white">
                  {{ org.display_name }}
                </h3>
                <p v-if="org.description" class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  {{ org.description }}
                </p>
                <p v-else class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  {{ t('web.organizations.no_description') }}
                </p>
              </div>
              <div class="ml-4 flex items-center gap-3">
                <span
                  v-if="org.is_default"
                  class="inline-flex items-center rounded-full bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 dark:bg-blue-900/20 dark:text-blue-400">
                  {{ t('web.organizations.default') }}
                </span>
                <button
                  @click="handleManageOrganization(org)"
                  class="inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:text-brand-500 dark:text-brand-400 dark:hover:text-brand-300">
                  {{ t('web.COMMON.manage') }}
                  <OIcon
                    collection="heroicons"
                    name="chevron-right"
                    class="size-4"
                    aria-hidden="true" />
                </button>
              </div>
            </div>
          </div>

          <!-- Empty State -->
          <div v-else class="py-12 text-center">
            <OIcon
              collection="heroicons"
              name="building-office-2"
              class="mx-auto size-12 text-gray-400"
              aria-hidden="true" />
            <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
              {{ t('web.organizations.no_organizations') }}
            </h3>
            <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {{ t('web.organizations.no_organizations_description') }}
            </p>
            <div class="mt-6">
              <button
                @click="handleCreateOrganization"
                class="inline-flex items-center gap-2 rounded-md bg-brand-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-brand-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-600 dark:bg-brand-500 dark:hover:bg-brand-400">
                <OIcon
                  collection="heroicons"
                  name="plus"
                  class="size-4"
                  aria-hidden="true" />
                {{ t('web.organizations.create_first_organization') }}
              </button>
            </div>
          </div>
        </div>
      </section>

      <!-- Info Section -->
      <section
        class="rounded-lg border border-blue-200 bg-blue-50 p-6 dark:border-blue-900/50 dark:bg-blue-900/10">
        <div class="flex gap-3">
          <OIcon
            collection="heroicons"
            name="information-circle"
            class="size-5 shrink-0 text-blue-600 dark:text-blue-400"
            aria-hidden="true" />
          <div class="text-sm">
            <h3 class="font-medium text-blue-900 dark:text-blue-300">
              {{ t('web.organizations.about_title') }}
            </h3>
            <p class="mt-1 text-blue-700 dark:text-blue-400">
              {{ t('web.organizations.about_description') }}
            </p>
          </div>
        </div>
      </section>
    </div>

    <!-- Create Organization Modal -->
    <CreateOrganizationModal
      :open="showCreateModal"
      @close="showCreateModal = false"
      @created="handleOrganizationCreated" />
  </SettingsLayout>
</template>
