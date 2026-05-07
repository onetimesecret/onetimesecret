<!-- src/apps/colonel/views/ColonelSystemRedis.vue -->

<script setup lang="ts">
  import { useColonelInfoStore } from '@/shared/stores/colonelInfoStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { redisMetrics, loading } = storeToRefs(store);
  const { fetchRedisMetrics } = store;

  const redisInfoArray = computed(() => {
    if (!redisMetrics.value) return [];
    return Object.entries(redisMetrics.value.redis_info).map(([key, value]) => ({
      key,
      value: value || '',
    }));
  });

  onMounted(() => fetchRedisMetrics());
</script>

<template>
  <div>
    <div
      v-if="loading.redisMetrics"
      class="text-center">
      {{ t('web.LABELS.loading') }}
    </div>

    <div v-else-if="redisMetrics">
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Redis Metrics</h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          Complete Redis INFO output ({{ formatDisplayDateTime(redisMetrics.timestamp) }})
        </p>
      </div>

      <div class="rounded-lg bg-white p-6 dark:bg-gray-800">
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
            <thead class="bg-gray-50 dark:bg-gray-700">
              <tr>
                <th
                  class="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                  Key
                </th>
                <th
                  class="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                  Value
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-900">
              <tr
                v-for="item in redisInfoArray"
                :key="item.key"
                class="hover:bg-gray-50 dark:hover:bg-gray-800">
                <td class="px-6 py-2 font-mono text-sm text-gray-900 dark:text-white">
                  {{ item.key }}
                </td>
                <td class="px-6 py-2 font-mono text-sm text-gray-600 dark:text-gray-300">
                  {{ item.value }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</template>
