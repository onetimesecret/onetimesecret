<!-- src/views/colonel/ColonelUsers.vue -->

<script setup lang="ts">
  import { useColonelInfoStore } from '@/stores/colonelInfoStore';
  import { storeToRefs } from 'pinia';
  import { onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { users, usersPagination, isLoading } = storeToRefs(store);
  const { fetchUsers } = store;

  onMounted(() => fetchUsers());
</script>

<template>
  <div class="p-6">
    <div
      v-if="isLoading"
      class="text-center">
      {{ t('web.LABELS.loading') }}
    </div>

    <div v-else>
      <!-- Page header -->
      <div class="mb-6">
        <h1 class="text-2xl font-bold text-gray-900 dark:text-white">
          {{ t('web.colonel.users') }}
        </h1>
        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
          {{ t('web.colonel.usersDescription') }}
        </p>
      </div>

      <!-- Pagination info -->
      <div
        v-if="usersPagination"
        class="mb-4 text-sm text-gray-600 dark:text-gray-400">
        Showing {{ users.length }} of {{ usersPagination.total_count }} users
      </div>

      <!-- Users table -->
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              <th
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Email
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Role
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Verified
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Plan
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Secrets
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Created
              </th>
              <th
                class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Last Login
              </th>
            </tr>
          </thead>
          <tbody class="bg-white dark:bg-gray-900 divide-y divide-gray-200 dark:divide-gray-700">
            <tr
              v-for="user in users"
              :key="user.user_id"
              class="hover:bg-gray-50 dark:hover:bg-gray-800">
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                {{ user.email }}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                <span
                  :class="{
                    'px-2 py-1 rounded bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200':
                      user.role === 'colonel',
                    'px-2 py-1 rounded bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200':
                      user.role === 'customer',
                  }">
                  {{ user.role }}
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                <span v-if="user.verified">✓</span>
                <span
                  v-else
                  class="text-gray-400">
                  -
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                {{ user.planid || 'None' }}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                {{ user.secrets_count }}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                {{ user.created_human }}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
                {{ user.last_login_human }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Empty state -->
      <div
        v-if="users.length === 0"
        class="text-center py-12 text-gray-500 dark:text-gray-400">
        No users found
      </div>
    </div>
  </div>
</template>
