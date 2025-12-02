<!-- src/views/colonel/ColonelSecrets.vue -->

<script setup lang="ts">
  import { useColonelInfoStore } from '@/shared/stores/colonelInfoStore';
  import { storeToRefs } from 'pinia';
  import { onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { secrets, secretsPagination, isLoading } = storeToRefs(store);
  const { fetchSecrets } = store;

  onMounted(() => fetchSecrets());
</script>

<template>
  <div class="p-6">
    <div
      v-if="isLoading"
      class="text-center">
      {{ t('web.LABELS.loading') }}
    </div>

    <div v-else>
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Secrets</h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          View and manage all secrets in the system
        </p>
      </div>

      <div
        v-if="secretsPagination"
        class="mb-4 text-sm text-gray-600 dark:text-gray-400">
        Showing {{ secrets.length }} of {{ secretsPagination.total_count }} secrets
      </div>

      <div
        v-if="secrets.length > 0"
        class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                Short ID
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                State
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                Created
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                Expiration
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                Age (days)
              </th>
            </tr>
          </thead>
          <tbody class="bg-white dark:bg-gray-900 divide-y divide-gray-200 dark:divide-gray-700">
            <tr
              v-for="secret in secrets"
              :key="secret.secret_id"
              class="hover:bg-gray-50 dark:hover:bg-gray-800">
              <td class="px-6 py-4 whitespace-nowrap text-sm font-mono text-gray-900 dark:text-white">
                {{ secret.shortid }}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                <span
                  :class="{
                    'px-2 py-1 rounded bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200':
                      secret.state === 'new',
                    'px-2 py-1 rounded bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200':
                      secret.state === 'received',
                    'px-2 py-1 rounded bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200':
                      secret.state === 'viewed',
                  }">
                  {{ secret.state }}
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                {{ secret.created_human }}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                {{ secret.expiration_human || 'Never' }}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                {{ Math.floor(secret.age / 86400) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        v-else
        class="text-center py-12 text-gray-500 dark:text-gray-400">
        No secrets found
      </div>
    </div>
  </div>
</template>
