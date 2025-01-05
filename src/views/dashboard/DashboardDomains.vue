<script setup lang="ts">
import CustomDomainsCTA from '@/components/ctas/CustomDomainsCTA.vue'
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import DomainsTable from '@/components/DomainsTable.vue';
import { useDomainsManager } from '@/composables/useDomainsManager';
import { WindowService } from '@/services/window.service';
import { computed, onMounted, ref } from 'vue';
import type { Plan, CustomDomain } from '@/schemas/models';

const plan = ref<Plan>(WindowService.get('plan'));

// const domainsStore = useDomainsStore() as DomainsStore;

const {
  isLoading,
  confirmDelete,
  records,
  error,
  fetch,
} = useDomainsManager();

const planAllowsCustomDomains = computed(() => plan.value.options?.custom_domains === true);

const domains = computed(() => {
  if (records.value) {
    return records.value;
  }
  return [] as CustomDomain[];
});

onMounted(() => {
  fetch()
});
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
      <CustomDomainsCTA />
    </div>

    <div
      v-else-if="domains.length === 0"
      class="py-8 text-center text-gray-500 dark:text-gray-400">
      No domains found.
      <router-link
        to="/domains/add"
        class="text-brandcomp-600 underline hover:text-brandcomp-700 dark:text-brandcomp-400 dark:hover:text-brandcomp-300">
        Add a domain
      </router-link>
      to get started.
    </div>
    <DomainsTable
      v-else
      :domains="domains"
      :is-loading="isLoading"
      @confirm-delete="confirmDelete"
    />
  </div>
</template>
