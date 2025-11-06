<!--  -->
<script setup lang="ts">
import DomainsTable from '@/components/DomainsTable.vue';
import ErrorDisplay from '@/components/ErrorDisplay.vue';
import EmptyState from '@/components/EmptyState.vue';
import { useDomainsManager } from '@/composables/useDomainsManager';
import { computed, onMounted } from 'vue';
import type { CustomDomain } from '@/schemas/models';
import TableSkeleton from '@/components/closet/TableSkeleton.vue'

const {
  isLoading,
  records,
  recordCount,
  error,
  refreshRecords,
} = useDomainsManager();

const domains = computed(() => {
  if (records.value) {
    return records.value;
  }
  return [] as CustomDomain[];
});

onMounted(() => {
  refreshRecords()
});
</script>

<template>
  <div>
    <ErrorDisplay v-if="error" :error="error" />
    <div v-if="isLoading">
      <TableSkeleton/>
    </div>

    <div v-else>
      <DomainsTable
        v-if="recordCount > 0"
        :domains="domains"
        :is-loading="isLoading"
      />

      <EmptyState
        v-else
        actionRoute="/domains/add"
        actionText="Add a Domain">
        <template #title>
          {{ $t('no-domains-found') }}
        </template>
        <template #description>
        {{ $t('get-started-by-adding-a-custom-domain') }}
        </template>
      </EmptyState>
    </div>
  </div>
</template>
