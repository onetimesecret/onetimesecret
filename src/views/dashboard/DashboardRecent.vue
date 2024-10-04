<template>
  <div>
    <DashboardTabNav />

    <SecretMetadataTable :hasItems="details?.has_items"
                        :notReceived="details?.notreceived"
                        :received="details?.received"
                        :isLoading="isLoading"
                        title="Received" />
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue';
import { useFetchData } from '@/composables/useFetchData';
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import SecretMetadataTable from '@/components/secrets/SecretMetadataTable.vue';
import { MetadataData } from '@/types/onetime';

const { details, fetchData: fetchDomains, isLoading } = useFetchData<MetadataData>({
  url: '/api/v2/private/recent',
});

onMounted(fetchDomains);


</script>
