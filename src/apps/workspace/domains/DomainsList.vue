<!-- src/apps/workspace/domains/DomainsList.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import TableSkeleton from '@/shared/components/closet/TableSkeleton.vue'
import DomainsTable from '@/apps/workspace/components/domains/DomainsTable.vue';
import EmptyState from '@/shared/components/ui/EmptyState.vue';
import ErrorDisplay from '@/shared/components/ui/ErrorDisplay.vue';
import { useDomainsManager } from '@/shared/composables/useDomainsManager';
import type { CustomDomain } from '@/schemas/models';
import { computed, onMounted } from 'vue';

const { t } = useI18n(); // auto-import

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
  <div class="container mx-auto min-w-[320px] max-w-2xl">
    <ErrorDisplay v-if="error" :error="error" />
    <div v-if="isLoading">
      <TableSkeleton />
    </div>

    <div v-else>
      <DomainsTable
        v-if="recordCount > 0"
        :domains="domains"
        :is-loading="isLoading" />

      <EmptyState
        v-else
        :showAction="true"
        action-route="/domains/add"
        action-text="Add a Domain">
        <template #title>
          {{ t('no-domains-found') }}
        </template>
        <template #description>
          {{ t('get-started-by-adding-a-custom-domain') }}
        </template>
      </EmptyState>
    </div>
  </div>
</template>
