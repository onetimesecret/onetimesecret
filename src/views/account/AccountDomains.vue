<template>
  <main>
    <div class="py-4 mb-16">

      <DomainsTable :shrimp="shrimp" :domains="domains" />
    </div>
  </main>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { CustomDomain } from '@/types/onetime';
import DomainsTable from '@/components/DomainsTable.vue';
import { useFetchData } from '@/composables/useFetchData';

const shrimp = ref(window.shrimp);

const { records: domains, fetchData: fetchDomains } = useFetchData<CustomDomain>({
  url: '/api/v2/account/domains',
});

onMounted(fetchDomains);

</script>
