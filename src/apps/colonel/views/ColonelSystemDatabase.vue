<!-- src/apps/colonel/views/ColonelSystemDatabase.vue -->

<script setup lang="ts">
  import { useColonelInfoStore } from '@/shared/stores/colonelInfoStore';
  import { storeToRefs } from 'pinia';
  import { onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { databaseMetrics, isLoading } = storeToRefs(store);
  const { fetchDatabaseMetrics } = store;

  // Type guard for database size entries (can be object or string from Redis INFO)
  const getDbKeys = (dbInfo: unknown): number => {
    if (typeof dbInfo === 'object' && dbInfo !== null && 'keys' in dbInfo) {
      return (dbInfo as { keys: number }).keys;
    }
    return 0;
  };

  const getDbExpires = (dbInfo: unknown): number => {
    if (typeof dbInfo === 'object' && dbInfo !== null && 'expires' in dbInfo) {
      return (dbInfo as { expires: number }).expires;
    }
    return 0;
  };

  onMounted(() => fetchDatabaseMetrics());
</script>

<template>
  <div class="p-6">
    <div
      v-if="isLoading"
      class="text-center">
      {{ t('web.LABELS.loading') }}
    </div>

    <div v-else-if="databaseMetrics">
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Database Metrics</h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">Redis database information and statistics</p>
      </div>

      <!-- Redis Info -->
      <div class="mb-6 bg-white dark:bg-gray-800 rounded-lg p-6">
        <h2 class="text-xl font-semibold mb-4 text-gray-900 dark:text-white">Redis Server</h2>
        <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Version</div>
            <div class="text-lg font-mono text-gray-900 dark:text-white">
              {{ databaseMetrics.redis_info.redis_version }}
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Mode</div>
            <div class="text-lg font-mono text-gray-900 dark:text-white">
              {{ databaseMetrics.redis_info.redis_mode }}
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Uptime</div>
            <div class="text-lg font-mono text-gray-900 dark:text-white">
              {{ databaseMetrics.redis_info.uptime_in_days }} days
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Connected Clients</div>
            <div class="text-lg font-mono text-gray-900 dark:text-white">
              {{ databaseMetrics.redis_info.connected_clients }}
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Ops/sec</div>
            <div class="text-lg font-mono text-gray-900 dark:text-white">
              {{ databaseMetrics.redis_info.instantaneous_ops_per_sec }}
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Total Commands</div>
            <div class="text-lg font-mono text-gray-900 dark:text-white">
              {{ databaseMetrics.redis_info.total_commands_processed.toLocaleString() }}
            </div>
          </div>
        </div>
      </div>

      <!-- Memory Stats -->
      <div class="mb-6 bg-white dark:bg-gray-800 rounded-lg p-6">
        <h2 class="text-xl font-semibold mb-4 text-gray-900 dark:text-white">Memory</h2>
        <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Used Memory</div>
            <div class="text-lg font-mono text-gray-900 dark:text-white">
              {{ databaseMetrics.memory_stats.used_memory_human }}
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">RSS Memory</div>
            <div class="text-lg font-mono text-gray-900 dark:text-white">
              {{ databaseMetrics.memory_stats.used_memory_rss_human }}
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Peak Memory</div>
            <div class="text-lg font-mono text-gray-900 dark:text-white">
              {{ databaseMetrics.memory_stats.used_memory_peak_human }}
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Fragmentation Ratio</div>
            <div class="text-lg font-mono text-gray-900 dark:text-white">
              {{ databaseMetrics.memory_stats.mem_fragmentation_ratio.toFixed(2) }}
            </div>
          </div>
        </div>
      </div>

      <!-- Database Sizes -->
      <div class="mb-6 bg-white dark:bg-gray-800 rounded-lg p-6">
        <h2 class="text-xl font-semibold mb-4 text-gray-900 dark:text-white">Databases</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div
            v-for="(dbInfo, dbName) in databaseMetrics.database_sizes"
            :key="dbName"
            class="border border-gray-200 dark:border-gray-700 rounded p-4">
            <div class="font-semibold text-gray-900 dark:text-white">{{ dbName }}</div>
            <div class="mt-2 text-sm text-gray-600 dark:text-gray-400">
              {{ getDbKeys(dbInfo).toLocaleString() }} keys, {{ getDbExpires(dbInfo).toLocaleString() }} with TTL
            </div>
          </div>
        </div>
        <div class="mt-4 text-sm text-gray-600 dark:text-gray-400">
          Total keys: {{ databaseMetrics.total_keys.toLocaleString() }}
        </div>
      </div>

      <!-- Model Counts -->
      <div class="bg-white dark:bg-gray-800 rounded-lg p-6">
        <h2 class="text-xl font-semibold mb-4 text-gray-900 dark:text-white">Model Counts</h2>
        <div class="grid grid-cols-3 gap-4">
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Customers</div>
            <div class="text-2xl font-bold text-gray-900 dark:text-white">
              {{ databaseMetrics.model_counts.customers.toLocaleString() }}
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Secrets</div>
            <div class="text-2xl font-bold text-gray-900 dark:text-white">
              {{ databaseMetrics.model_counts.secrets.toLocaleString() }}
            </div>
          </div>
          <div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Metadata</div>
            <div class="text-2xl font-bold text-gray-900 dark:text-white">
              {{ databaseMetrics.model_counts.metadata.toLocaleString() }}
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
