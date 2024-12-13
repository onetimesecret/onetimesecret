<script setup lang="ts">
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import EmptyState from '@/components/EmptyState.vue';
import SecretMetadataTable from '@/components/secrets/SecretMetadataTable.vue';
import { MetadataListItem, isMetadataListItemDetails } from '@/schemas/models/metadata';
import { useMetadataStore } from '@/stores/metadataStore';
import { storeToRefs } from 'pinia';
import { onMounted, onUnmounted, computed } from 'vue';

const store = useMetadataStore();
const { records, details, isLoading, error } = storeToRefs(store);

// Add computed properties for received and not received items
const receivedItems = computed(() => {
  if (details.value && isMetadataListItemDetails(details.value)) {
    return details.value.received;
  }
  return [] as MetadataListItem[];
});

const notReceivedItems = computed(() => {
  if (details.value && isMetadataListItemDetails(details.value)) {
    return details.value.notreceived;
  }
  return [] as MetadataListItem[];
});

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
        :notReceived="notReceivedItems"
        :received="receivedItems"
        :isLoading="isLoading"
      />
      <EmptyState v-else />
    </div>
  </div>
</template>
