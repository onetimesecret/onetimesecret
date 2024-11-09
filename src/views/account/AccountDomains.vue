<template>
  <div class="dark:bg-gray-900">
    <DashboardTabNav />
    <div v-if="isLoading"
         class="text-center py-8 dark:text-gray-200">
      <p>Loading domains...</p>
    </div>
    <div v-else-if="error"
         class="bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200 p-4 rounded">
      {{ error }}
    </div>
    <div v-else-if="!planAllowsCustomDomains"
         class="w-full">
      <!-- Upgrade Modal Component -->
      <UpgradeIdentityModal :is-open="isUpgradeModalOpen"
                            to="/plans/identity"
                            @close="closeUpgradeModal"
                            @upgrade="handleUpgrade" />

      <!-- Upgrade CTA Section -->
      <div
           class="w-full p-6 bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700">
        <div class="flex flex-col lg:flex-row items-center justify-between gap-6">
          <!-- Left side content -->
          <div class="flex-1 space-y-4">
            <div class="flex items-center gap-3">
              <span class="inline-flex items-center justify-center p-2 bg-brand-100 dark:bg-brand-900 rounded-lg">
                <svg xmlns="http://www.w3.org/2000/svg"
                     class="h-6 w-6 text-brand-600 dark:text-brand-400"
                     fill="none"
                     viewBox="0 0 24 24"
                     stroke="currentColor">
                  <path stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9" />
                </svg>
              </span>
              <h2 class="text-xl font-semibold text-gray-900 dark:text-white">
                Identity Plus
              </h2>
            </div>

            <p class="text-gray-600 dark:text-gray-300 max-w-xl">
              Secure your brand, build customer trust with links from your domain.
            </p>

            <ul class="space-y-3">
              <li class="flex items-center gap-2 text-gray-600 dark:text-gray-300">
                <svg class="h-5 w-5 text-green-500"
                     fill="none"
                     viewBox="0 0 24 24"
                     stroke="currentColor">
                  <path stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M5 13l4 4L19 7" />
                </svg>
                Unlimited custom domains
              </li>
              <li class="flex items-center gap-2 text-gray-600 dark:text-gray-300">
                <svg class="h-5 w-5 text-green-500"
                     fill="none"
                     viewBox="0 0 24 24"
                     stroke="currentColor">
                  <path stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M5 13l4 4L19 7" />
                </svg>
                Privacy-first design
              </li>
              <li class="flex items-center gap-2 text-gray-600 dark:text-gray-300">
                <svg class="h-5 w-5 text-green-500"
                     fill="none"
                     viewBox="0 0 24 24"
                     stroke="currentColor">
                  <path stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M5 13l4 4L19 7" />
                </svg>
                Full API access
              </li>
            </ul>
          </div>

          <!-- Right side CTA -->
          <div class="flex flex-col items-center lg:items-end gap-4">
            <div class="text-center lg:text-right mb-2">
              <p class="text-2xl font-bold text-gray-900 dark:text-white">$35</p>
              <p class="text-sm text-gray-500 dark:text-gray-400">per month</p>
            </div>
            <button @click="openUpgradeModal"
                    class="inline-flex items-center px-6 py-3 border border-transparent text-base font-medium rounded-lg text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 transition-colors duration-200"
                    aria-label="Start today with Identity Plus">
              <span>Start today</span>
              <svg class="ml-2 -mr-1 h-5 w-5"
                   fill="none"
                   viewBox="0 0 24 24"
                   stroke="currentColor">
                <path stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M17 8l4 4m0 0l-4 4m4-4H3" />
              </svg>
            </button>
            <p class="text-sm text-gray-500 dark:text-gray-400">
              Meets and exceeds compliance standards
            </p>
          </div>
        </div>
      </div>
    </div>


    <div v-else-if="domains.length === 0"
         class="text-center py-8 text-gray-500 dark:text-gray-400">
      No domains found.
      <router-link to="/account/domains/add"
                   class="underline text-brandcomp-600 hover:text-brandcomp-700 dark:text-brandcomp-400 dark:hover:text-brandcomp-300">
        Add a domain</router-link>
      to get started.
    </div>
    <DomainsTable v-else
                  :domains="domains"
                  :isToggling="isToggling"
                  :isSubmitting="isSubmitting"
                  @confirm-delete="handleConfirmDelete"
                  @toggle-homepage="handleToggleHomepage" />
  </div>
</template>

<script setup lang="ts">
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import DomainsTable from '@/components/DomainsTable.vue';
import UpgradeIdentityModal from '@/components/modals/UpgradeIdentityModal.vue';
import { useDomainsManager } from '@/composables/useDomainsManager';
import { useWindowProps } from '@/composables/useWindowProps';
import { useDomainsStore } from '@/stores/domainsStore';
import { useNotificationsStore } from '@/stores/notifications';
import type { CustomDomain } from '@/types';
import { computed, onMounted, ref } from 'vue';
const isUpgradeModalOpen = ref(false)

const openUpgradeModal = () => {
  isUpgradeModalOpen.value = true
}

const closeUpgradeModal = () => {
  isUpgradeModalOpen.value = false
}

const handleUpgrade = () => {
  // Handle any additional logic here when the user has clicked the upgrade button.
};

const { plan } = useWindowProps(['plan'])

const domainsStore = useDomainsStore();
const notifications = useNotificationsStore();

const {
  isToggling,
  setTogglingStatus,
  isSubmitting,
  confirmDelete
} = useDomainsManager();

const planAllowsCustomDomains = computed(() => plan.value.options?.custom_domains === true);
const domains = computed(() => domainsStore.domains);
const isLoading = computed(() => domainsStore.isLoading);
const error = ref<string | null>(null);

onMounted(async () => {
  try {
    console.debug('[AccountDomains] Attempting to refresh domains');
    await domainsStore.refreshDomains();
  } catch (err) {
    console.error('Failed to refresh domains:', err);
    error.value = err instanceof Error
      ? `Failed to refresh domains: ${err.message}`
      : 'An unknown error occurred while refreshing domains';
  }
});

const handleConfirmDelete = async (domainId: string) => {
  const confirmedDomainId = await confirmDelete(domainId);
  if (confirmedDomainId) {
    try {
      await domainsStore.deleteDomain(confirmedDomainId);
      notifications.show(`Removed ${domainId}`, 'success');
    } catch (err) {
      console.error('Failed to delete domain:', err);
      notifications.show('Could not remove domain at this time', 'error');
      error.value = err instanceof Error
        ? err.message
        : 'Failed to delete domain';
    }
  }
};


const handleToggleHomepage = async (domain: CustomDomain) => {
  // Set the toggling state immediately
  const domainId = domain.display_domain;
  setTogglingStatus(domainId, true);

  try {
    const newState = await domainsStore.toggleHomepageAccess(domain);

    notifications.show(
      `Homepage access ${newState ? 'enabled' : 'disabled'} for ${domainId}`,
      'success'
    );
  } catch (err) {
    console.error('Failed to toggle homepage:', err);
    error.value = err instanceof Error
      ? err.message
      : 'Failed to toggle homepage';

    notifications.show(
      `Failed to update homepage access for ${domainId}`,
      'error'
    );
  } finally {
    // Clear the toggling state
    setTogglingStatus(domainId, false);
  }
};
</script>
