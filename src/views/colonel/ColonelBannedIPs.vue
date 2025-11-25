<!-- src/views/colonel/ColonelBannedIPs.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { useColonelInfoStore } from '@/stores/colonelInfoStore';
  import { formatDate } from '@/utils/format';
  import { storeToRefs } from 'pinia';
  import { onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { bannedIPs, currentIP, isLoading } = storeToRefs(store);
  const { fetchBannedIPs, banIP, unbanIP } = store;

  const newIP = ref('');
  const newReason = ref('');
  const showBanForm = ref(false);
  const errorMessage = ref('');
  const successMessage = ref('');

  const clearMessages = () => {
    errorMessage.value = '';
    successMessage.value = '';
  };

  const handleBan = async () => {
    if (!newIP.value) return;

    clearMessages();

    try {
      await banIP(newIP.value, newReason.value);
      successMessage.value = `IP address ${newIP.value} has been banned`;
      newIP.value = '';
      newReason.value = '';
      showBanForm.value = false;

      // Auto-clear success message after 5 seconds
      setTimeout(() => {
        successMessage.value = '';
      }, 5000);
    } catch (error: any) {
      // Extract error message from API response
      if (error.response?.data?.message) {
        errorMessage.value = error.response.data.message;
      } else if (error.message) {
        errorMessage.value = error.message;
      } else {
        errorMessage.value = 'Failed to ban IP address';
      }
      console.error('Failed to ban IP:', error);
    }
  };

  const handleUnban = async (ipAddress: string) => {
    if (!confirm(`Unban ${ipAddress}?`)) return;

    clearMessages();

    try {
      await unbanIP(ipAddress);
      successMessage.value = `IP address ${ipAddress} has been unbanned`;

      // Auto-clear success message after 5 seconds
      setTimeout(() => {
        successMessage.value = '';
      }, 5000);
    } catch (error: any) {
      // Extract error message from API response
      if (error.response?.data?.message) {
        errorMessage.value = error.response.data.message;
      } else if (error.message) {
        errorMessage.value = error.message;
      } else {
        errorMessage.value = 'Failed to unban IP address';
      }
      console.error('Failed to unban IP:', error);
    }
  };

  onMounted(() => fetchBannedIPs());
</script>

<template>
  <div class="p-6">
    <div
      v-if="isLoading"
      class="text-center">
      {{ t('web.LABELS.loading') }}
    </div>

    <div v-else>
      <div class="mb-6 flex justify-between items-center">
        <div>
          <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Banned IPs</h1>
          <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            Manage IP addresses banned from accessing the system
          </p>
        </div>
        <button
          @click="showBanForm = !showBanForm"
          class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700">
          {{ showBanForm ? 'Cancel' : 'Ban IP' }}
        </button>
      </div>

      <!-- Error Message -->
      <div
        v-if="errorMessage"
        class="mb-6 rounded-lg border border-red-200 bg-red-50 p-4 dark:border-red-700 dark:bg-red-900/20">
        <div class="flex items-start justify-between">
          <div class="flex items-start">
            <OIcon
              collection="heroicons"
              name="exclamation-triangle"
              class="mr-3 mt-0.5 size-5 text-red-500 dark:text-red-400" />
            <div>
              <p class="text-sm font-medium text-red-800 dark:text-red-200">Error</p>
              <p class="mt-1 text-sm text-red-700 dark:text-red-300">
                {{ errorMessage }}
              </p>
            </div>
          </div>
          <button
            @click="errorMessage = ''"
            class="text-red-500 hover:text-red-700 dark:text-red-400 dark:hover:text-red-200">
            <OIcon
              collection="heroicons"
              name="x-mark"
              class="size-5" />
          </button>
        </div>
      </div>

      <!-- Success Message -->
      <div
        v-if="successMessage"
        class="mb-6 rounded-lg border border-green-200 bg-green-50 p-4 dark:border-green-700 dark:bg-green-900/20">
        <div class="flex items-start justify-between">
          <div class="flex items-start">
            <OIcon
              collection="heroicons"
              name="check-circle"
              class="mr-3 mt-0.5 size-5 text-green-500 dark:text-green-400" />
            <div>
              <p class="text-sm font-medium text-green-800 dark:text-green-200">Success</p>
              <p class="mt-1 text-sm text-green-700 dark:text-green-300">
                {{ successMessage }}
              </p>
            </div>
          </div>
          <button
            @click="successMessage = ''"
            class="text-green-500 hover:text-green-700 dark:text-green-400 dark:hover:text-green-200">
            <OIcon
              collection="heroicons"
              name="x-mark"
              class="size-5" />
          </button>
        </div>
      </div>

      <!-- Current IP Address Info -->
      <div
        v-if="currentIP"
        class="mb-6 rounded-lg border border-blue-200 bg-blue-50 p-4 dark:border-blue-700 dark:bg-blue-900/20">
        <div class="flex items-center justify-between">
          <div class="flex items-center">
            <OIcon
              collection="heroicons"
              name="information-circle"
              class="mr-3 size-5 text-blue-500 dark:text-blue-400" />
            <div>
              <p class="text-sm font-medium text-blue-800 dark:text-blue-200">
                Your Current IP Address
              </p>
              <p class="mt-1 font-mono text-lg font-semibold text-blue-900 dark:text-blue-100">
                {{ currentIP }}
              </p>
            </div>
          </div>
          <button
            @click="newIP = currentIP; showBanForm = true"
            class="rounded px-3 py-1.5 text-sm text-blue-700 hover:bg-blue-100 dark:text-blue-300 dark:hover:bg-blue-800/50">
            Quick Ban
          </button>
        </div>
      </div>

      <!-- Ban form -->
      <div
        v-if="showBanForm"
        class="mb-6 bg-white dark:bg-gray-800 rounded-lg p-6">
        <h2 class="text-lg font-semibold mb-4 text-gray-900 dark:text-white">Ban IP Address</h2>
        <div class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              IP Address *
            </label>
            <input
              v-model="newIP"
              type="text"
              placeholder="192.168.1.1"
              class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Reason</label>
            <input
              v-model="newReason"
              type="text"
              placeholder="Optional reason"
              class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white" />
          </div>
          <button
            @click="handleBan"
            :disabled="!newIP"
            class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed">
            Ban IP
          </button>
        </div>
      </div>

      <!-- Banned IPs list -->
      <div class="bg-white dark:bg-gray-800 rounded-lg overflow-hidden">
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
            <thead class="bg-gray-50 dark:bg-gray-700">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                  IP Address
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                  Reason
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                  Banned At
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                  Banned By
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white dark:bg-gray-900 divide-y divide-gray-200 dark:divide-gray-700">
              <tr
                v-for="ip in bannedIPs"
                :key="ip.id"
                class="hover:bg-gray-50 dark:hover:bg-gray-800">
                <td class="px-6 py-4 text-sm font-mono text-gray-900 dark:text-white">
                  {{ ip.ip_address }}
                </td>
                <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-300">
                  {{ ip.reason || '-' }}
                </td>
                <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-300">
                  {{ formatDate(ip.banned_at) }}
                </td>
                <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-300">
                  {{ ip.banned_by || '-' }}
                </td>
                <td class="px-6 py-4 text-right">
                  <button
                    @click="handleUnban(ip.ip_address)"
                    class="text-red-600 hover:text-red-800 dark:text-red-400 dark:hover:text-red-300 text-sm font-medium">
                    Unban
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="bannedIPs.length === 0"
          class="text-center py-12 text-gray-500 dark:text-gray-400">
          No banned IPs
        </div>
      </div>
    </div>
  </div>
</template>
