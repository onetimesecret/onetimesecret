<template>
  <div class="">
    <DashboardTabNav />
    <DomainsTable :domains="domains" />
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue';
import { CustomDomain } from '@/types/onetime';
import DomainsTable from '@/components/DomainsTable.vue';
import { useFetchData } from '@/composables/useFetchData';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';

const { records: domains, fetchData: fetchDomains } = useFetchData<CustomDomain>({
  url: '/api/v2/account/domains',
});

onMounted(fetchDomains);

</script>
