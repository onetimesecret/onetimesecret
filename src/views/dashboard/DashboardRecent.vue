
<script setup lang="ts">
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import EmptyState from '@/components/EmptyState.vue';
import SecretMetadataTable from '@/components/secrets/SecretMetadataTable.vue';
import { useMetadataStore } from '@/stores/metadataStore';
import { storeToRefs } from 'pinia';
import { onMounted, onUnmounted } from 'vue';

const store = useMetadataStore();
const { records, details, isLoading, error } = storeToRefs(store);

onMounted(async () => {
  await store.fetchList();

});

onUnmounted(() => {
  store.abortPendingRequests();
});
</script>

<template>
  <div>
    <DashboardTabNav />

    <div v-if="isLoading">
      Loading...
    </div>
    <div v-else-if="error">
      {{ error }}
    </div>
    <div v-else>
      <SecretMetadataTable
        v-if="records.length > 0"
        :not-received="details?.notreceived"
        :received="details?.received"
        :is-loading="isLoading"
        title="Received"
      />
      <EmptyState v-else />
    </div>
  </div>
</template>
