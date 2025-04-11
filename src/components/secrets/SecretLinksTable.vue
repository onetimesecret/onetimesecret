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

  const hasSecrets = computed(() => props.concealedMessages.length > 0);

  const handleCopy = () => {
    toastMessage.value = t('web.clipboard.copied');
    showToast.value = true;
    setTimeout(() => {
      showToast.value = false;
    }, 1500);
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
        {{ $t('web.LABELS.timeline') }}
      </h3>

      <span v-if="hasSecrets" class="text-sm text-gray-500 dark:text-gray-400">
        {{ $t('web.LABELS.items_count', {count: concealedMessages.length}) }}
      </span>
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
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-slate-800">
            <tr>
              <th
                scope="col"
                class="px-6 py-2.5 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400">
                {{ $t('web.LABELS.secret_link') }}
              </th>
              <th
                scope="col"
                class="px-6 py-2.5 text-left text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400 hidden sm:table-cell">
                {{ $t('details') }}
              </th>
              <th
                scope="col"
                class="px-6 py-2.5 text-right text-xs font-medium text-gray-500 uppercase tracking-wider dark:text-gray-400">
                  {{ $t('web.LABELS.actions') }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
            <SecretLinksTableRow
              v-for="concealedMessage in concealedMessages"
              :key="concealedMessage.id"
              :concealed-message="concealedMessage"
              @copy="handleCopy"
              @delete="handleBurn"
            />
          </tbody>
        </table>
      </div>

      <ToastNotification
        :show="showToast"
        :message="toastMessage"
      />
    </div>
  </div>
</template>
