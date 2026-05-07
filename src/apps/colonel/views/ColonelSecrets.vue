<!-- src/apps/colonel/views/ColonelSecrets.vue -->

<script setup lang="ts">
  import ColonelFetchError from '@/apps/colonel/components/ColonelFetchError.vue';
  import { useColonelInfoStore } from '@/shared/stores/colonelInfoStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const stateLabels = computed(() => ({
    new: t('web.colonel.secrets.state.new'),
    received: t('web.colonel.secrets.state.received'),
    viewed: t('web.colonel.secrets.state.viewed'),
  }));

  const store = useColonelInfoStore();
  const { secrets, secretsPagination, loading, secretsFetchError } = storeToRefs(store);
  const { fetchSecrets } = store;

  onMounted(() => fetchSecrets());
</script>

<template>
  <div>
    <div
      v-if="loading.secrets"
      class="py-12 text-center">
      {{ t('web.LABELS.loading') }}
    </div>

    <div v-else>
      <!-- Back navigation -->
      <div class="mb-4">
        <router-link
          to="/colonel"
          class="inline-flex items-center text-sm text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200">
          <svg
            class="mr-1 size-4"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M15 19l-7-7 7-7" />
          </svg>
          {{ t('web.COMMON.back') }}
        </router-link>
      </div>

      <div class="mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.colonel.secrets.title') }}
        </h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.colonel.secrets.description') }}
        </p>
      </div>

      <ColonelFetchError
        v-if="secretsFetchError"
        :schema="secretsFetchError"
        resource="secrets" />

      <div
        v-else-if="secretsPagination"
        class="mb-4 text-sm text-gray-600 dark:text-gray-400">
        Showing {{ secrets.length }} of {{ secretsPagination.total_count }} secrets
      </div>

      <div
        v-if="!secretsFetchError && secrets.length > 0"
        class="overflow-x-auto">
        <table
          data-testid="colonel-secrets-table"
          class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                {{ t('web.colonel.secrets.columns.shortId') }}
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                {{ t('web.colonel.secrets.columns.state') }}
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                {{ t('web.colonel.secrets.columns.created') }}
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                {{ t('web.colonel.secrets.columns.expiration') }}
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                {{ t('web.colonel.secrets.columns.age') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-900">
            <tr
              v-for="secret in secrets"
              :key="secret.secret_id"
              class="hover:bg-gray-50 dark:hover:bg-gray-800">
              <td
                class="whitespace-nowrap px-6 py-4 font-mono text-sm text-gray-900 dark:text-white">
                {{ secret.shortid }}
              </td>
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                <span
                  :class="{
                    'rounded bg-green-100 px-2 py-1 text-green-800 dark:bg-green-900 dark:text-green-200':
                      secret.state === 'new',
                    'rounded bg-yellow-100 px-2 py-1 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200':
                      secret.state === 'received',
                    'rounded bg-gray-100 px-2 py-1 text-gray-800 dark:bg-gray-900 dark:text-gray-200':
                      secret.state === 'viewed',
                  }">
                  {{ stateLabels[secret.state as keyof typeof stateLabels] || secret.state }}
                </span>
              </td>
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                {{ formatDisplayDateTime(secret.created) }}
              </td>
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                {{ secret.expiration ? formatDisplayDateTime(secret.expiration) : t('web.colonel.secrets.never') }}
              </td>
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                {{ Math.floor(secret.age / 86400) }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        v-else-if="!secretsFetchError"
        class="py-12 text-center text-gray-500 dark:text-gray-400">
        {{ t('web.colonel.secrets.empty') }}
      </div>
    </div>
  </div>
</template>
