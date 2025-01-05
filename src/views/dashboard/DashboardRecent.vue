<script setup lang="ts">
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import EmptyState from '@/components/EmptyState.vue';
import ErrorDisplay from '@/components/ErrorDisplay.vue';
import SecretMetadataTable from '@/components/secrets/SecretMetadataTable.vue';
import { MetadataRecords } from '@/schemas/api/endpoints';
import { useMetadataList } from '@/composables/useMetadataList';
import { onMounted, computed } from 'vue';

// Define props
interface Props {
}
defineProps<Props>();

const { records, details, isLoading, fetch, error } = useMetadataList();

// Add computed properties for received and not received items
const receivedItems = computed(() => {
  if (details.value) {
    return details.value.received;
  }
  return [] as MetadataRecords[];
});

const notReceivedItems = computed(() => {
  if (details.value) {
    return details.value.notreceived;
  }
  return [] as MetadataRecords[];
});

onMounted(() => {
  fetch()
});

</script>

<template>
  <div>
    <DashboardTabNav />

    <ErrorDisplay v-if="error" :error="error" />
    <div v-else-if="isLoading">
      Loading...
    </div>
    <div v-else>
      <SecretMetadataTable
        v-if="records?.length > 0"
        :not-received="notReceivedItems"
        :received="receivedItems"
        :is-loading="isLoading"
      />
      <EmptyState v-else />
    </div>
  </div>
</template>
