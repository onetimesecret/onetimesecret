<!-- src/components/colonel/QueueStatus.vue -->

<script setup lang="ts">
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useColonelInfoStore } from '@/stores/colonelInfoStore';

const { t } = useI18n();
const colonelStore = useColonelInfoStore();

onMounted(async () => {
  try {
    await colonelStore.fetchQueueMetrics();
  } catch (error) {
    console.error('Failed to fetch queue metrics:', error);
  }
});

const queueMetrics = computed(() => colonelStore.queueMetrics);

const connectionStatus = computed(() => {
  if (!queueMetrics.value?.connection) return 'unknown';
  return queueMetrics.value.connection.connected ? 'connected' : 'disconnected';
});

const connectionStatusClass = computed(() => {
  switch (connectionStatus.value) {
    case 'connected':
      return 'text-green-600 dark:text-green-400';
    case 'disconnected':
      return 'text-red-600 dark:text-red-400';
    default:
      return 'text-gray-500 dark:text-gray-400';
  }
});

const workerHealthClass = computed(() => {
  const health = queueMetrics.value?.worker_health?.status;
  switch (health) {
    case 'healthy':
      return 'text-green-600 dark:text-green-400';
    case 'degraded':
      return 'text-yellow-600 dark:text-yellow-400';
    case 'unhealthy':
      return 'text-red-600 dark:text-red-400';
    default:
      return 'text-gray-500 dark:text-gray-400';
  }
});
</script>

<template>
  <div class="rounded-lg bg-white p-4 shadow dark:bg-gray-800">
    <h3 class="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
      {{ t('web.colonel.backgroundJobs') }}
    </h3>

    <!-- Connection Status -->
    <div v-if="queueMetrics?.connection" class="mb-4">
      <div class="flex items-center justify-between">
        <span class="text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.colonel.connectionStatus') }}
        </span>
        <span class="text-sm font-medium" :class="connectionStatusClass">
          {{ connectionStatus }}
        </span>
      </div>
      <div v-if="queueMetrics.connection.host" class="mt-1 text-xs text-gray-500 dark:text-gray-500">
        {{ queueMetrics.connection.host }}
      </div>
    </div>

    <!-- Worker Health -->
    <div v-if="queueMetrics?.worker_health" class="mb-4">
      <div class="flex items-center justify-between">
        <span class="text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.colonel.workerHealth') }}
        </span>
        <span class="text-sm font-medium" :class="workerHealthClass">
          {{ queueMetrics.worker_health.status }}
        </span>
      </div>
      <div v-if="queueMetrics.worker_health.active_workers !== undefined" class="mt-1 text-xs text-gray-500 dark:text-gray-500">
        {{ queueMetrics.worker_health.active_workers }} {{ t('web.colonel.activeWorkers') }}
      </div>
    </div>

    <!-- Queue Metrics Table -->
    <div v-if="queueMetrics?.queues?.length" class="overflow-x-auto">
      <h4 class="mb-2 text-sm font-semibold text-gray-700 dark:text-gray-300">
        {{ t('web.colonel.queueStatus') }}
      </h4>
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-gray-200 dark:border-gray-700">
            <th class="pb-2 pr-4 text-left font-medium text-gray-600 dark:text-gray-400">
              {{ t('web.colonel.queueName') }}
            </th>
            <th class="px-2 pb-2 text-right font-medium text-gray-600 dark:text-gray-400">
              {{ t('web.colonel.pendingMessages') }}
            </th>
            <th class="px-2 pb-2 text-right font-medium text-gray-600 dark:text-gray-400">
              {{ t('web.colonel.consumers') }}
            </th>
            <th class="pl-2 pb-2 text-right font-medium text-gray-600 dark:text-gray-400">
              {{ t('web.colonel.processingRate') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="queue in queueMetrics.queues"
            :key="queue.name"
            class="border-b border-gray-100 dark:border-gray-700/50">
            <td class="py-2 pr-4 text-gray-900 dark:text-gray-100">
              {{ queue.name }}
            </td>
            <td class="px-2 py-2 text-right text-gray-700 dark:text-gray-300">
              {{ queue.pending_messages }}
            </td>
            <td class="px-2 py-2 text-right text-gray-700 dark:text-gray-300">
              {{ queue.consumers }}
            </td>
            <td class="pl-2 py-2 text-right text-gray-700 dark:text-gray-300">
              {{ queue.rate !== undefined ? queue.rate.toFixed(2) : 'N/A' }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Empty State -->
    <div
      v-else-if="!colonelStore.isLoading"
      class="py-8 text-center text-sm text-gray-500 dark:text-gray-400">
      {{ t('web.colonel.noQueueData') }}
    </div>

    <!-- Loading State -->
    <div
      v-if="colonelStore.isLoading"
      class="py-8 text-center text-sm text-gray-500 dark:text-gray-400">
      {{ t('web.colonel.loadingQueueData') }}
    </div>
  </div>
</template>
