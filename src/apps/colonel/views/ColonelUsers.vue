<!-- src/apps/colonel/views/ColonelUsers.vue -->

<script setup lang="ts">
  import ColonelListPage from '@/apps/colonel/components/ColonelListPage.vue';
  import ColonelPagination from '@/apps/colonel/components/ColonelPagination.vue';
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
  <ColonelListPage
    :loading="loading.users"
    :title="t('web.colonel.users')"
    :description="t('web.colonel.usersDescription')"
    :fetch-error="usersFetchError"
    resource="users">
    <template #count>
      <template v-if="usersPagination">
        Showing {{ users.length }} of {{ usersPagination.total_count }} users
      </template>
    </template>

    <!-- Users table -->
    <div
      v-if="users.length > 0"
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
      v-else
      class="py-12 text-center text-gray-500 dark:text-gray-400">
      No users found
    </div>

    <!-- Pagination -->
    <ColonelPagination
      v-if="usersPagination"
      :pagination="usersPagination"
      :loading="loading.users"
      class="mt-4"
      @update:page="(page) => fetchUsers(page, usersPagination?.per_page ?? 50)"
      @update:per-page="(perPage) => fetchUsers(1, perPage)" />
  </ColonelListPage>
</template>
