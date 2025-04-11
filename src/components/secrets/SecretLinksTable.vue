<script setup lang="ts">
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { ref, computed } from 'vue';
  import SecretLinksTableRow from './SecretLinksTableRow.vue';
  import ToastNotification from '@/components/ui/ToastNotification.vue';
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/components/icons/OIcon.vue';

  const { t } = useI18n();

  const props = defineProps<{
    concealedMessages: ConcealedMessage[];
  }>();

  // Toast notification state
  const showToast = ref(false);
  const toastMessage = ref('');

  // Toggle state for displaying expired secrets
  const showExpired = ref(false);

  const hasSecrets = computed(() => props.concealedMessages.length > 0);

  // Group secrets by status
  const groupedSecrets = computed(() => {
    const active: ConcealedMessage[] = [];
    const expired: ConcealedMessage[] = [];

    props.concealedMessages.forEach(message => {
      // Consider a secret expired if TTL is <= 0 or it's marked as burned
      const isExpired = message.clientInfo.ttl <= 0;
      const isBurned = !!message.response.record.metadata?.burned;

      if (isExpired || isBurned) {
        expired.push(message);
      } else {
        active.push(message);
      }
    });

    return { active, expired };
  });

  // Computed properties for active and expired secrets
  const activeSecrets = computed(() => groupedSecrets.value.active);
  const expiredSecrets = computed(() => groupedSecrets.value.expired);
  const hasExpiredSecrets = computed(() => expiredSecrets.value.length > 0);
  // const hasActiveSecrets = computed(() => activeSecrets.value.length > 0);

  // Sort secrets by creation time (most recent first)
  const sortedActiveSecrets = computed(() => {
    return [...activeSecrets.value].sort((a, b) => {
      // Sort by creation time, newest first
      return b.clientInfo.createdAt.getTime() - a.clientInfo.createdAt.getTime();
    });
  });

  const sortedExpiredSecrets = computed(() => {
    return [...expiredSecrets.value].sort((a, b) => {
      // Sort by creation time, newest first
      return b.clientInfo.createdAt.getTime() - a.clientInfo.createdAt.getTime();
    });
  });

  const toggleExpiredSecrets = () => {
    showExpired.value = !showExpired.value;
  };

  const handleCopy = () => {
    // Copy feedback is now handled by the tooltip in SecretLinksTableRow
  };

  const handleBurn = (concealedMessage: ConcealedMessage) => {
    // Here you would add logic to delete the message, e.g.,
    // through a store or service call
    console.log('Deleting message', concealedMessage.id);
    toastMessage.value = t('web.secrets.messageDeleted');
    showToast.value = true;
    setTimeout(() => {
      showToast.value = false;
    }, 1500);
  };
</script>

<template>
  <div class="recent-secrets mt-8">

    <div class="flex items-center justify-between mb-3">
      <h3 class="text-lg font-medium text-gray-700 dark:text-gray-200">
        {{ $t('web.COMMON.recent') }}
      </h3>

      <div class="flex items-center gap-2">
        <span v-if="hasSecrets" class="text-sm text-gray-500 dark:text-gray-400">
          {{ $t('web.LABELS.items_count', {count: activeSecrets.length}) }}
          <span v-if="hasExpiredSecrets" class="ml-1">
            ({{ $t('web.LABELS.expired_count', {count: expiredSecrets.length}) }})
          </span>
        </span>
      </div>
    </div>

    <div v-if="!hasSecrets" class="flex flex-col items-center justify-center py-8 bg-gray-50 dark:bg-slate-800/30 rounded-lg border border-gray-200 dark:border-gray-700">
      <OIcon
        collection="heroicons"
        name="document-text"
        class="size-10 text-gray-400 dark:text-gray-500 mb-3" />
      <p class="text-gray-500 dark:text-gray-400">{{ $t('web.secrets.noRecents') }}</p>
    </div>

    <div
      v-else
      class="relative overflow-hidden rounded-lg border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-slate-900 opacity-90">
      <div class="overflow-x-auto">
        <!-- Active Secrets Table -->
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-slate-800">
            <tr>
              <th
                scope="col"
                class="px-6 py-2.5 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400">
                {{ $t('web.LABELS.receipts') }}
              </th>
              <th
                scope="col"
                class="px-6 py-2.5 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400 hidden sm:table-cell">
                {{ $t('web.LABELS.details') }}
              </th>
              <th
                scope="col"
                class="px-6 py-2.5 text-right text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400">
                  {{ $t('web.LABELS.share') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <SecretLinksTableRow
              v-for="concealedMessage in sortedActiveSecrets"
              :key="concealedMessage.id"
              :concealed-message="concealedMessage"
              @copy="handleCopy"
              @delete="handleBurn"
            />
          </tbody>
        </table>

        <!-- Expired Secrets Section -->
        <div v-if="hasExpiredSecrets" class="border-t border-gray-200 dark:border-gray-700 mt-2">
          <div
            @click="toggleExpiredSecrets"
            class="flex items-center justify-between px-6 py-3 bg-gray-50 dark:bg-slate-800 cursor-pointer hover:bg-gray-100 dark:hover:bg-slate-700 transition-colors">
            <div class="flex items-center">
              <OIcon
                collection="heroicons"
                :name="showExpired ? 'chevron-down' : 'chevron-right'"
                class="size-4 text-gray-500 dark:text-gray-400 mr-2" />
              <span class="text-sm font-medium text-gray-700 dark:text-gray-300">
                {{ $t('web.LABELS.expired_secrets', {count: expiredSecrets.length}) }}
              </span>
            </div>
          </div>

          <!-- Expandable Expired Secrets Table -->
          <div v-if="showExpired">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
              <tbody class="divide-y divide-gray-200 dark:divide-gray-700 bg-gray-50/50 dark:bg-slate-800/50">
                <SecretLinksTableRow
                  v-for="concealedMessage in sortedExpiredSecrets"
                  :key="concealedMessage.id"
                  :concealed-message="concealedMessage"
                  @copy="handleCopy"
                  @delete="handleBurn"
                />
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <ToastNotification
        :show="showToast"
        :message="toastMessage"
      />
    </div>
  </div>
</template>
