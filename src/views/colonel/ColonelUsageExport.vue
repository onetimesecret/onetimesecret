<!-- src/views/colonel/ColonelUsageExport.vue -->

<script setup lang="ts">
  import { useColonelInfoStore } from '@/stores/colonelInfoStore';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { usageExport, isLoading } = storeToRefs(store);
  const { fetchUsageExport } = store;

  const startDate = ref('');
  const endDate = ref('');

  const defaultDates = () => {
    const end = new Date();
    const start = new Date();
    start.setDate(start.getDate() - 30);
    startDate.value = start.toISOString().split('T')[0];
    endDate.value = end.toISOString().split('T')[0];
  };

  const handleFetch = async () => {
    const start = startDate.value ? new Date(startDate.value).getTime() / 1000 : undefined;
    const end = endDate.value ? new Date(endDate.value).getTime() / 1000 : undefined;
    await fetchUsageExport(start, end);
  };

  const secretsByDayArray = computed(() => {
    if (!usageExport.value) return [];
    return Object.entries(usageExport.value.secrets_by_day)
      .map(([date, count]) => ({ date, count }))
      .sort((a, b) => a.date.localeCompare(b.date));
  });

  const usersByDayArray = computed(() => {
    if (!usageExport.value) return [];
    return Object.entries(usageExport.value.users_by_day)
      .map(([date, count]) => ({ date, count }))
      .sort((a, b) => a.date.localeCompare(b.date));
  });

  onMounted(() => {
    defaultDates();
    handleFetch();
  });
</script>

<template>
  <div class="p-6">
    <div class="mb-6">
      <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Usage Export</h1>
      <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">Export usage data for a specific date range</p>
    </div>

    <!-- Date range selector -->
    <div class="mb-6 bg-white dark:bg-gray-800 rounded-lg p-6">
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Start Date</label>
          <input
            v-model="startDate"
            type="date"
            class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white" />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">End Date</label>
          <input
            v-model="endDate"
            type="date"
            class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white" />
        </div>
        <div class="flex items-end">
          <button
            @click="handleFetch"
            :disabled="isLoading"
            class="w-full px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50">
            {{ isLoading ? 'Loading...' : 'Fetch Data' }}
          </button>
        </div>
      </div>
    </div>

    <div v-if="usageExport">
      <!-- Summary Stats -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <div class="bg-white dark:bg-gray-800 rounded-lg p-6">
          <div class="text-sm text-gray-500 dark:text-gray-400">Total Secrets</div>
          <div class="text-3xl font-bold text-gray-900 dark:text-white">
            {{ usageExport.usage_data.total_secrets.toLocaleString() }}
          </div>
        </div>
        <div class="bg-white dark:bg-gray-800 rounded-lg p-6">
          <div class="text-sm text-gray-500 dark:text-gray-400">New Users</div>
          <div class="text-3xl font-bold text-gray-900 dark:text-white">
            {{ usageExport.usage_data.total_new_users.toLocaleString() }}
          </div>
        </div>
        <div class="bg-white dark:bg-gray-800 rounded-lg p-6">
          <div class="text-sm text-gray-500 dark:text-gray-400">Avg Secrets/Day</div>
          <div class="text-3xl font-bold text-gray-900 dark:text-white">
            {{ usageExport.usage_data.avg_secrets_per_day.toFixed(1) }}
          </div>
        </div>
        <div class="bg-white dark:bg-gray-800 rounded-lg p-6">
          <div class="text-sm text-gray-500 dark:text-gray-400">Avg Users/Day</div>
          <div class="text-3xl font-bold text-gray-900 dark:text-white">
            {{ usageExport.usage_data.avg_users_per_day.toFixed(1) }}
          </div>
        </div>
      </div>

      <!-- Daily breakdown tables -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <!-- Secrets by day -->
        <div class="bg-white dark:bg-gray-800 rounded-lg p-6">
          <h2 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">Secrets by Day</h2>
          <div class="max-h-96 overflow-y-auto">
            <table class="min-w-full">
              <thead class="sticky top-0 bg-gray-50 dark:bg-gray-700">
                <tr>
                  <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400">Date</th>
                  <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 dark:text-gray-400">Count</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                <tr
                  v-for="item in secretsByDayArray"
                  :key="item.date">
                  <td class="px-4 py-2 text-sm text-gray-900 dark:text-white">{{ item.date }}</td>
                  <td class="px-4 py-2 text-sm text-right text-gray-900 dark:text-white">{{ item.count }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <!-- Users by day -->
        <div class="bg-white dark:bg-gray-800 rounded-lg p-6">
          <h2 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">New Users by Day</h2>
          <div class="max-h-96 overflow-y-auto">
            <table class="min-w-full">
              <thead class="sticky top-0 bg-gray-50 dark:bg-gray-700">
                <tr>
                  <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400">Date</th>
                  <th class="px-4 py-2 text-right text-xs font-medium text-gray-500 dark:text-gray-400">Count</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                <tr
                  v-for="item in usersByDayArray"
                  :key="item.date">
                  <td class="px-4 py-2 text-sm text-gray-900 dark:text-white">{{ item.date }}</td>
                  <td class="px-4 py-2 text-sm text-right text-gray-900 dark:text-white">{{ item.count }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
