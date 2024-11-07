<template>
  <div>
    <DashboardTabNav />
    <div v-if="isLoading"
         class="text-center py-8">
      <p>Loading domains...</p>
    </div>
    <div v-else-if="error"
         class="bg-red-100 text-red-800 p-4 rounded">
      {{ error }}
    </div>
    <div v-else-if="domains.length === 0"
         class="text-center py-8 text-gray-500">
      No domains found. Add a domain to get started.
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
import DomainsTable from '@/components/DomainsTable.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import { useDomainsManager } from '@/composables/useDomainsManager';
import { useDomainsStore } from '@/stores/domainsStore';
import type { CustomDomain } from '@/types/onetime';
import { computed, onMounted, ref } from 'vue';
import { useNotificationsStore } from '@/stores/notifications';

const domainsStore = useDomainsStore();
const notifications = useNotificationsStore()

const {
  isToggling,
  isSubmitting,
  toggleHomepageCreation,
  confirmDelete
} = useDomainsManager();

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
  try {
    await toggleHomepageCreation(domain);
    notifications.show(
      `Homepage access ${!domain?.brand?.allow_public_homepage ? 'enabled' : 'disabled'} for ${domain.display_domain}`,
      'success'
    );
  } catch (err) {
    console.error('Failed to toggle homepage:', err);
    error.value = err instanceof Error
      ? err.message
      : 'Failed to toggle homepage';

    notifications.show(
      `Failed to update homepage access for ${domain.display_domain}`,
      'error'
    );
  }
};
</script>
