<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { formatDistanceToNow } from 'date-fns';
  import { ref } from 'vue';

  defineProps<{
    concealedMessages: ConcealedMessage[];
  }>();

  // Copy functionality state
  const copiedId = ref<string | null>(null);
  const showToast = ref(false);

  const formatTTL = (seconds: number): string => {
    if (seconds >= 86400) return `${Math.floor(seconds / 86400)} days`;
    if (seconds >= 3600) return `${Math.floor(seconds / 3600)} hours`;
    return `${Math.floor(seconds / 60)} minutes`;
  };

  const copyToClipboard = async (concealedMessage: ConcealedMessage) => {
    try {
      await navigator.clipboard.writeText(concealedMessage.secret_key);
      copiedId.value = concealedMessage.id;
      showToast.value = true;

      // Reset copy state
      setTimeout(() => {
        copiedId.value = null;
      }, 2000);

      // Hide toast
      setTimeout(() => {
        showToast.value = false;
      }, 1500);
    } catch (err) {
      console.error('Failed to copy text: ', err);
    }
  };
</script>

<template>
  <div
    class="relative overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-slate-900">
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
        <thead class="bg-gray-50 dark:bg-slate-800">
          <tr>
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400"
              >Share Link</th
            >
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400"
              >Security</th
            >
            <th
              scope="col"
              class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400"
              >Expires</th
            >
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
          <tr
            v-for="concealedMessage in concealedMessages"
            :key="concealedMessage.id"
            class="group hover:bg-gray-50 dark:hover:bg-slate-800/50 transition-colors">
            <td class="px-6 py-4">
              <div class="flex items-center gap-2">
                <span
                  class="font-mono text-sm text-gray-900 dark:text-gray-100 truncate max-w-[300px]">
                  {{ concealedMessage.secret_key }}
                </span>
                <button
                  @click="() => copyToClipboard(concealedMessage)"
                  class="p-1.5 rounded-md text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 transition-colors duration-150"
                  :class="{
                    'text-green-500 dark:text-green-400': copiedId === concealedMessage.id,
                  }"
                  :title="copiedId === concealedMessage.id ? 'Copied!' : 'Copy to clipboard'">
                  <OIcon
                    collection="material-symbols"
                    :name="copiedId === concealedMessage.id ? 'check' : 'content-copy-outline'"
                    class="w-4 h-4" />
                </button>
              </div>
              <span class="text-sm text-gray-500 dark:text-gray-400">
                {{
                  formatDistanceToNow(concealedMessage.clientInfo.createdAt, { addSuffix: true })
                }}
              </span>
            </td>
            <td class="px-6 py-4">
              <div class="flex items-center gap-2">
                <div
                  class="flex items-center gap-1.5 text-sm"
                  :class="
                    concealedMessage.clientInfo.hasPassphrase
                      ? 'text-amber-600 dark:text-amber-400'
                      : 'text-gray-500 dark:text-gray-400'
                  ">
                  <OIcon
                    collection="material-symbols"
                    :name="concealedMessage.clientInfo.hasPassphrase ? 'key-vertical' : 'lock-open'"
                    class="w-4 h-4" />
                  <span>{{
                    concealedMessage.clientInfo.hasPassphrase ? 'Protected' : 'No passphrase'
                  }}</span>
                </div>
              </div>
            </td>
            <td class="px-6 py-4">
              <span
                class="inline-flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400">
                <OIcon
                  collection="material-symbols"
                  name="timer"
                  class="w-4 h-4" />
                {{ formatTTL(concealedMessage.clientInfo.ttl) }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Copy Feedback Toast -->
    <div
      v-if="showToast"
      class="absolute top-3 right-3 px-3 py-1.5 bg-gray-900 dark:bg-gray-700 text-white text-sm rounded-md shadow-lg transform transition-all duration-300"
      :class="{
        'opacity-0 translate-y-1': !showToast,
        'opacity-100 translate-y-0': showToast,
      }">
      Copied to clipboard
    </div>
  </div>
</template>
