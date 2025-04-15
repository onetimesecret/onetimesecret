<!-- src/components/secrets/SecretLinksTable.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import ToastNotification from '@/components/ui/ToastNotification.vue';
  import { type ConcealedMessage } from '@/types/ui/concealed-message';
  import { computed, ref } from 'vue';
  import { useI18n } from 'vue-i18n';

  import SecretLinksTableRow from './SecretLinksTableRow.vue';

  const { t } = useI18n();

  const props = defineProps<{
    concealedMessages: ConcealedMessage[];
    ariaLabelledBy?: string;
  }>();

  // Toast notification state
  const showToast = ref(false);
  const toastMessage = ref('');

  const hasSecrets = computed(() => props.concealedMessages.length > 0);

  // Sort secrets by creation time (most recent first)
  const sortedSecrets = computed(() => {
    return [...props.concealedMessages].sort((a, b) => {
      // Sort by creation time, newest first
      return b.clientInfo.createdAt.getTime() - a.clientInfo.createdAt.getTime();
    });
  });

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
  <div class="mt-8">
    <!-- No secrets state -->
    <!-- prettier-ignore-attribute class -->
    <div
      v-if="!hasSecrets"
      class="flex flex-col items-center justify-center
        rounded-lg border border-gray-200 bg-gray-50 py-8 dark:border-gray-700
        dark:bg-slate-800/30"
      role="status">
      <OIcon
        collection="heroicons"
        name="document-text"
        class="mb-3 size-10 text-gray-400 dark:text-gray-500"
        aria-hidden="true" />
      <p class="text-gray-500 dark:text-gray-400">
        {{ $t('web.dashboard.title_no_recent_secrets') }}
      </p>
    </div>

    <!-- Table with secrets -->
    <!-- prettier-ignore-attribute class -->
    <div
      v-else
      class="relative overflow-hidden
        rounded-lg border border-gray-200 bg-white opacity-90 shadow-sm
        dark:border-gray-700 dark:bg-slate-900">
      <div class="overflow-x-auto">
        <!-- Secrets Table -->
        <table
          class="min-w-full divide-y divide-gray-200 dark:divide-gray-700"
          :aria-labelledby="ariaLabelledBy">
          <caption class="sr-only">
            {{ $t('web.LABELS.caption_recent_secrets') }}
          </caption>
          <thead class="bg-gray-50 dark:bg-slate-800">
            <tr>
              <!-- prettier-ignore-attribute class -->
              <th
                scope="col"
                class="px-6 py-2.5 text-left text-xs font-medium uppercase tracking-wider
                  text-gray-500 dark:text-gray-400">
                {{ $t('web.LABELS.receipts') }}
              </th>
              <!-- prettier-ignore-attribute class -->
              <th
                scope="col"
                class="hidden px-6 py-2.5 text-left text-xs font-medium uppercase tracking-wider
                  text-gray-500 dark:text-gray-400 sm:table-cell">
                {{ $t('web.LABELS.details') }}
              </th>
              <!-- prettier-ignore-attribute class -->
              <th
                scope="col"
                class="px-6 py-2.5 text-right text-xs font-medium uppercase tracking-wider
                  text-gray-500 dark:text-gray-400">
                {{ $t('web.LABELS.share') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <SecretLinksTableRow
              v-for="concealedMessage in sortedSecrets"
              :key="concealedMessage.id"
              :concealed-message="concealedMessage"
              @copy="handleCopy"
              @delete="handleBurn" />
          </tbody>
        </table>
      </div>

      <ToastNotification
        :show="showToast"
        :message="toastMessage"
        aria-live="polite" />
    </div>
  </div>
</template>
