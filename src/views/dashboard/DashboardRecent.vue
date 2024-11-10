
<template>
  <div>
    <DashboardTabNav />

    <div v-if="isLoading">Loading...</div>
    <div v-else-if="error">{{ error }}</div>
    <div v-else>
      <MetadataList
        :metadata-records="records"
        v-if="records.length > 0" />
      <EmptyState v-else />
    </div>
  </div>
</template>

<script setup lang="ts">
import { useMetadataStore } from '@/stores/metadataStore';
import { storeToRefs } from 'pinia';
import { onMounted, onUnmounted } from 'vue';

const store = useMetadataStore();
const { records, isLoading, error } = storeToRefs(store);

onMounted(async () => {
  await store.fetchList();
});

onUnmounted(() => {
  store.abortPendingRequests();
});
</script>
