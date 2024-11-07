<template>
  <div>
    <DashboardTabNav />
    <div v-if="isLoading" class="text-center py-8">
      <p>Loading domains...</p>
    </div>
    <div v-else-if="error" class="bg-red-100 text-red-800 p-4 rounded">
      {{ error }}
    </div>
    <div v-else-if="domains.length === 0" class="text-center py-8 text-gray-500">
      No domains found. Add a domain to get started.
    </div>
    <DomainsTable
      v-else
      :domains="domains"
      :removeDomain="removeDomain"
    />
  </div>
</template>

<script setup lang="ts">
import { onMounted, computed, ref } from 'vue';
import { useDomainsStore } from '@/stores/domainsStore';
import DomainsTable from '@/components/DomainsTable.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import { useDomainsManager } from '@/composables/useDomainsManager';

const domainsStore = useDomainsStore();

// Computed properties to access store state
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


const {
  isToggling,
  isSubmitting,
  toggleHomepageCreation,
  confirmDelete
} = useDomainsManager(localDomains.value);

const handleConfirmDelete = async (domainId: string) => {
  const confirmedDomainId = await confirmDelete(domainId);
  if (confirmedDomainId) {
    try {
      await domainsStore.deleteDomain(confirmedDomainId);
    } catch (err) {
      console.error('Failed to delete domain:', err);
    }
  }
};
</script>
