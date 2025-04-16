<script setup lang="ts">
  import TableSkeleton from '@/components/closet/TableSkeleton.vue';
  import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
  import EmptyState from '@/components/EmptyState.vue';
  import ErrorDisplay from '@/components/ErrorDisplay.vue';
  import SecretMetadataTable from '@/components/secrets/SecretMetadataTable.vue';
  import { useMetadataList } from '@/composables/useMetadataList';
  import { MetadataRecords } from '@/schemas/api/endpoints';
  import { onMounted, computed } from 'vue';

  // Define props
  interface Props {}
  defineProps<Props>();

  const { details, recordCount, isLoading, refreshRecords, error } = useMetadataList();

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
    refreshRecords();
  });
</script>

<template>
  <div>
    <DashboardTabNav />

    <ErrorDisplay
      v-if="error"
      :error="error" />

    <div v-else-if="isLoading">
      <TableSkeleton />
    </div>

    <div v-else>
      <SecretMetadataTable
        v-if="recordCount > 0"
        :not-received="notReceivedItems"
        :received="receivedItems"
        :is-loading="isLoading" />
      <EmptyState
        v-else
        actionRoute="/"
        :actionText="$t('create-a-secret')">
        <template #title>
          {{ $t('web.dashboard.title_no_recent_secrets') }}
        </template>
        <template #description>
          <div>{{ $t('web.dashboard.get-started-by-creating-your-first-secret') }}</div>
          <div>{{ $t('theyll-appear-here-once-youve-shared-them') }}</div>
        </template>
      </EmptyState>
    </div>
  </div>
</template>
