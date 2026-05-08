<!-- src/apps/colonel/views/ColonelBannedIPs.vue -->

<script setup lang="ts">
  import ColonelListPage from '@/apps/colonel/components/ColonelListPage.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useColonelInfoStore } from '@/shared/stores/colonelInfoStore';
  import { formatDisplayDateTime } from '@/utils/format';
  import { AxiosError } from 'axios';
  import { storeToRefs } from 'pinia';
  import { onMounted, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();

  const store = useColonelInfoStore();
  const { bannedIPs, currentIP, loading } = storeToRefs(store);
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
      successMessage.value = t('web.colonel.bannedIps.success.banned', { ip: newIP.value });
      newIP.value = '';
      newReason.value = '';
      showBanForm.value = false;

      // Auto-clear success message after 5 seconds
      setTimeout(() => {
        successMessage.value = '';
      }, 5000);
    } catch (error: unknown) {
      // Extract error message from API response
      if (error instanceof AxiosError && error.response?.data?.message) {
        errorMessage.value = error.response.data.message;
      } else if (error instanceof Error) {
        errorMessage.value = error.message;
      } else {
        errorMessage.value = t('web.colonel.bannedIps.error.banFailed');
      }
      console.error('Failed to ban IP:', error);
    }
  };

  const handleUnban = async (ipAddress: string) => {
    if (!confirm(t('web.colonel.bannedIps.confirmUnban', { ip: ipAddress }))) return;

    clearMessages();

    try {
      await unbanIP(ipAddress);
      successMessage.value = t('web.colonel.bannedIps.success.unbanned', { ip: ipAddress });

      // Auto-clear success message after 5 seconds
      setTimeout(() => {
        successMessage.value = '';
      }, 5000);
    } catch (error: unknown) {
      // Extract error message from API response
      if (error instanceof AxiosError && error.response?.data?.message) {
        errorMessage.value = error.response.data.message;
      } else if (error instanceof Error) {
        errorMessage.value = error.message;
      } else {
        errorMessage.value = t('web.colonel.bannedIps.error.unbanFailed');
      }
      console.error('Failed to unban IP:', error);
    }
  };

  onMounted(() => fetchBannedIPs());
</script>

<template>
  <ColonelListPage
    :loading="loading.bannedIPs"
    :title="t('web.colonel.bannedIps.title')"
    :description="t('web.colonel.bannedIps.description')">
    <template #header-extra>
      <div class="-mt-4 mb-6 flex justify-end">
        <button
          @click="showBanForm = !showBanForm"
          class="rounded bg-red-600 px-4 py-2 text-white hover:bg-red-700">
          {{ showBanForm ? t('web.colonel.bannedIps.actions.cancel') : t('web.colonel.bannedIps.actions.ban') }}
        </button>
      </div>
    </template>

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
              <p class="text-sm font-medium text-red-800 dark:text-red-200">{{ t('web.COMMON.error') }}</p>
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
              <p class="text-sm font-medium text-green-800 dark:text-green-200">{{ t('web.COMMON.success') }}</p>
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
                {{ t('web.colonel.bannedIps.currentIp') }}
              </p>
              <p class="mt-1 font-mono text-lg font-semibold text-blue-900 dark:text-blue-100">
                {{ currentIP }}
              </p>
            </div>
          </div>
          <button
            @click="
              newIP = currentIP;
              showBanForm = true;
            "
            class="rounded px-3 py-1.5 text-sm text-blue-700 hover:bg-blue-100 dark:text-blue-300 dark:hover:bg-blue-800/50">
            {{ t('web.colonel.bannedIps.actions.quickBan') }}
          </button>
        </div>
      </div>

      <!-- Ban form -->
      <div
        v-if="showBanForm"
        class="mb-6 rounded-lg bg-white p-6 dark:bg-gray-800">
        <h2 class="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
          {{ t('web.colonel.bannedIps.form.title') }}
        </h2>
        <div class="space-y-4">
          <div>
            <label class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.colonel.bannedIps.form.ipLabel') }} *
            </label>
            <input
              v-model="newIP"
              type="text"
              placeholder="192.168.1.1"
              class="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-gray-900 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
          </div>
          <div>
            <label class="mb-2 block text-sm font-medium text-gray-700 dark:text-gray-300">
              {{ t('web.colonel.bannedIps.form.reasonLabel') }}
            </label>
            <input
              v-model="newReason"
              type="text"
              :placeholder="t('web.colonel.bannedIps.form.reasonPlaceholder')"
              class="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-gray-900 dark:border-gray-600 dark:bg-gray-700 dark:text-white" />
          </div>
          <button
            @click="handleBan"
            :disabled="!newIP || loading.bannedIPs"
            class="rounded bg-red-600 px-4 py-2 text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50">
            {{ t('web.colonel.bannedIps.actions.ban') }}
          </button>
        </div>
      </div>

      <!-- Banned IPs list -->
      <div class="overflow-hidden rounded-lg bg-white dark:bg-gray-800">
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
            <thead class="bg-gray-50 dark:bg-gray-700">
              <tr>
                <th
                  class="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                  {{ t('web.colonel.bannedIps.columns.ipAddress') }}
                </th>
                <th
                  class="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                  {{ t('web.colonel.bannedIps.columns.reason') }}
                </th>
                <th
                  class="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                  {{ t('web.colonel.bannedIps.columns.bannedAt') }}
                </th>
                <th
                  class="px-6 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                  {{ t('web.colonel.bannedIps.columns.bannedBy') }}
                </th>
                <th
                  class="px-6 py-3 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                  {{ t('web.LABELS.actions') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200 bg-white dark:divide-gray-700 dark:bg-gray-900">
              <tr
                v-for="ip in bannedIPs"
                :key="ip.id"
                class="hover:bg-gray-50 dark:hover:bg-gray-800">
                <td class="px-6 py-4 font-mono text-sm text-gray-900 dark:text-white">
                  {{ ip.ip_address }}
                </td>
                <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-300">
                  {{ ip.reason || '-' }}
                </td>
                <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-300">
                  {{ formatDisplayDateTime(new Date(ip.banned_at * 1000)) }}
                </td>
                <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-300">
                  {{ ip.banned_by || '-' }}
                </td>
                <td class="px-6 py-4 text-right">
                  <button
                    @click="handleUnban(ip.ip_address)"
                    :disabled="loading.bannedIPs"
                    class="text-sm font-medium text-red-600 hover:text-red-800 disabled:opacity-50 dark:text-red-400 dark:hover:text-red-300">
                    {{ t('web.colonel.bannedIps.actions.unban') }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="bannedIPs.length === 0"
          class="py-12 text-center text-gray-500 dark:text-gray-400">
          {{ t('web.colonel.bannedIps.empty') }}
        </div>
      </div>
  </ColonelListPage>
</template>
