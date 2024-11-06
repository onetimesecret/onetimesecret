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
      :domains="domainsStore.domains"
    />

    <!-- Debug Information -->
    <div class="bg-yellow-100 p-4 mt-4 rounded">
      <h3 class="font-bold mb-2">Debugging Information</h3>
      <div>
        <strong>Domains Count:</strong>
        <pre class="text-xs">{{ domains.length }}</pre>
      </div>
      <div>
        <strong>Domains:</strong>
        <pre class="text-xs">{{ JSON.stringify(domains, null, 2) }}</pre>
      </div>
      <div>
        <strong>Store Domains Count:</strong>
        <pre class="text-xs">{{ domainsStore.domains.length }}</pre>
      </div>
      <div>
        <strong>Store Domains:</strong>
        <pre class="text-xs">{{ JSON.stringify(domainsStore.domains, null, 2) }}</pre>
      </div>
      <div>
        <strong>Loading State:</strong>
        <pre class="text-xs">{{ isLoading }}</pre>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted, computed, ref } from 'vue';
import { useDomainsStore } from '@/stores/domainsStore';
import DomainsTable from '@/components/DomainsTable.vue';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';

const domainsStore = useDomainsStore();

// Computed properties to access store state
const domains = computed(() => domainsStore.domains);
const isLoading = computed(() => domainsStore.isLoading);
const error = ref<string | null>(null);

onMounted(async () => {
  try {
    console.log('[AccountDomains] Attempting to refresh domains');
    await domainsStore.refreshDomains();
    console.log('[AccountDomains] Domains after refresh:', domainsStore.domains);
  } catch (err) {
    console.error('Failed to refresh domains:', err);
    error.value = err instanceof Error
      ? `Failed to refresh domains: ${err.message}`
      : 'An unknown error occurred while refreshing domains';
  }
});
</script>
