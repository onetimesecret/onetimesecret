<script setup lang="ts">
import AccountDomasCTA from '@/components/ctas/AccountDomainsCTA.vue'
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import DomainsTable from '@/components/DomainsTable.vue';
import { useDomainsManager } from '@/composables/useDomainsManager';
import { WindowService } from '@/services/window.service';
import { useDomainsStore, type DomainsStore } from '@/stores/domainsStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { computed, onMounted, ref } from 'vue';
import type { Plan } from '@/schemas/models';

const plan = ref<Plan>(WindowService.get('plan', null));

const domainsStore = useDomainsStore() as DomainsStore;
const notifications = useNotificationsStore();

const {
  isLoading,
  confirmDelete
} = useDomainsManager();

const planAllowsCustomDomains = computed(() => plan.value.options?.custom_domains === true);
const domains = computed(() => domainsStore.domains);
const error = ref<string | null>(null);

onMounted(async () => {
  try {
    console.debug('[DashboardDomains] Attempting to refresh domains');
    await domainsStore.refreshRecords();
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

</script>

<template>
  <div class="dark:bg-gray-900">

    <DashboardTabNav />

    <div
      v-if="isLoading"
      class="py-8 text-center dark:text-gray-200">
      <p>Loading domains...</p>
    </div>
    <div
      v-else-if="error"
      class="rounded bg-red-100 p-4 text-red-800 dark:bg-red-900 dark:text-red-200">
      {{ error }}
    </div>
    <div
      v-else-if="!planAllowsCustomDomains"
      class="w-full">
      <AccountDomasCTA />
    </div>

    <div
      v-else-if="domains.length === 0"
      class="py-8 text-center text-gray-500 dark:text-gray-400">
      No domains found.
      <router-link
        to="/account/domains/add"
        class="text-brandcomp-600 underline hover:text-brandcomp-700 dark:text-brandcomp-400 dark:hover:text-brandcomp-300">
        Add a domain
      </router-link>
      to get started.
    </div>
    <DomainsTable
      v-else
      :domains="domains"
      :is-loading="isLoading"
      @confirm-delete="handleConfirmDelete"
    />
  </div>
</template>
