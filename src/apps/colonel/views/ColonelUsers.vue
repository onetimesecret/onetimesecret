<!-- src/apps/colonel/views/ColonelUsers.vue -->

<script setup lang="ts">
  import ColonelFetchError from '@/apps/colonel/components/ColonelFetchError.vue';
  import { useColonelInfoStore } from '@/shared/stores/colonelInfoStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { users, usersPagination, loading, usersFetchError } = storeToRefs(store);
  const { fetchUsers } = store;

  onMounted(() => fetchUsers());
</script>

<template>
  <div>
    <div
      v-if="loading.users"
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

      <!-- Page header -->
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.colonel.users') }}
        </h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.colonel.usersDescription') }}
        </p>
      </div>

      <!-- Validation error: distinguish "schema mismatch" from "no users" -->
      <ColonelFetchError
        v-if="usersFetchError"
        :schema="usersFetchError"
        resource="users" />

      <!-- Pagination info -->
      <div
        v-else-if="usersPagination"
        class="mb-4 text-sm text-gray-600 dark:text-gray-400">
        Showing {{ users.length }} of {{ usersPagination.total_count }} users
      </div>

      <!-- Users table -->
      <div
        v-if="!usersFetchError && users.length > 0"
        class="overflow-x-auto">
        <table
          data-testid="colonel-users-table"
          class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                Email
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                Role
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                Verified
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                Plan
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                Secrets
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                Created
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
                Last Login
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-900">
            <tr
              v-for="user in users"
              :key="user.user_id"
              class="hover:bg-gray-50 dark:hover:bg-gray-800">
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                {{ user.email }}
              </td>
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                <span
                  :class="{
                    'rounded bg-red-100 px-2 py-1 text-red-800 dark:bg-red-900 dark:text-red-200':
                      user.role === 'colonel',
                    'rounded bg-blue-100 px-2 py-1 text-blue-800 dark:bg-blue-900 dark:text-blue-200':
                      user.role === 'customer',
                  }">
                  {{ user.role }}
                </span>
              </td>
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                <span v-if="user.verified">✓</span>
                <span
                  v-else
                  class="text-gray-400">
                  -
                </span>
              </td>
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                {{ user.planid || 'None' }}
              </td>
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                {{ user.secrets_count }}
              </td>
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                {{ formatDisplayDateTime(user.created) }}
              </td>
              <td class="whitespace-nowrap px-6 py-4 text-sm text-gray-900 dark:text-white">
                {{ user.last_login ? formatDisplayDateTime(user.last_login) : '—' }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Empty state -->
      <div
        v-else-if="!usersFetchError"
        class="py-12 text-center text-gray-500 dark:text-gray-400">
        No users found
      </div>
    </div>
  </div>
</template>
