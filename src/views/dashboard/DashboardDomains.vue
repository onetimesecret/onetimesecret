<script setup lang="ts">
import CustomDomainsCTA from '@/components/ctas/CustomDomainsCTA.vue'
import DashboardTabNav from '@/components/dashboard/DashboardTabNav.vue';
import DomainsTable from '@/components/DomainsTable.vue';
import ErrorDisplay from '@/components/ErrorDisplay.vue';
import EmptyState from '@/components/EmptyState.vue';
import { useDomainsManager } from '@/composables/useDomainsManager';
import { WindowService } from '@/services/window.service';
import { computed, onMounted, ref } from 'vue';
import type { Plan, CustomDomain } from '@/schemas/models';
import TableSkeleton from '@/components/closet/TableSkeleton.vue'

const plan = ref<Plan>(WindowService.get('plan'));

const {
  isLoading,
  deleteDomain,
  records,
  recordCount,
  error,
  refreshRecords,
} = useDomainsManager();

const planAllowsCustomDomains = computed(() => plan.value.options?.custom_domains === true);

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
    <DashboardTabNav />

    <ErrorDisplay v-if="error" :error="error" />
    <div v-if="isLoading">
      <TableSkeleton/>
    </div>

    <div
      v-else-if="!planAllowsCustomDomains"
      class="w-full">
      <CustomDomainsCTA />
    </div>

    <div v-else>
      <DomainsTable
        v-if="recordCount > 0"
        :domains="domains"
        :is-loading="isLoading"
        @delete="deleteDomain"
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
