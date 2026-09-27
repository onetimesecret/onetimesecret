<!-- src/apps/secret/components/SecretLinksTable.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import type { RecentSecretRecord } from '@/shared/composables/useRecentSecrets';
import { computed } from 'vue';

import SecretLinksTableRow from './SecretLinksTableRow.vue';

const { t } = useI18n();

const props = defineProps<{
  records: RecentSecretRecord[];
  ariaLabelledBy?: string;
}>();

const emit = defineEmits<{
  'update:memo': [id: string, memo: string];
}>();

const handleUpdateMemo = (id: string, memo: string) => {
  emit('update:memo', id, memo);
};

const hasSecrets = computed(() => props.records.length > 0);

// Sort secrets by creation time (most recent first)
const sortedSecrets = computed(() =>
  [...props.records].sort(
    (a, b) => b.createdAt.getTime() - a.createdAt.getTime()
  )
);

const handleCopy = () => {
  // Copy feedback is now handled by the tooltip in SecretLinksTableRow
};
</script>

<template>
  <div class="mt-6" role="group">
    <!-- No secrets state -->
    <div
      v-if="!hasSecrets"
      class="flex flex-col items-center justify-center rounded-xl border border-gray-200
        bg-gray-50/50 py-10 dark:border-gray-700/50 dark:bg-slate-800/20"
      role="status">
      <OIcon
        collection="heroicons"
        name="document-text"
        class="mb-3 size-12 text-gray-300 dark:text-gray-600"
        aria-hidden="true" />
      <p class="text-sm text-gray-500 dark:text-gray-400">
        {{ t('web.dashboard.title_no_recent_secrets') }}
      </p>
    </div>

    <!-- Timeline list with secrets -->
    <div
      v-else
      class="flow-root rounded-lg border border-gray-200/60 bg-white/60 p-4 shadow-sm backdrop-blur-sm
        dark:border-gray-700/60 dark:bg-gray-800/60 sm:p-6"
      :aria-labelledby="ariaLabelledBy">
      <span class="sr-only">{{ t('web.LABELS.caption_recent_secrets') }}</span>

      <ul role="list" class="-mb-2">
        <SecretLinksTableRow
          v-for="(record, idx) in sortedSecrets"
          :key="record.id"
          :record="record"
          :index="sortedSecrets.length - idx"
          :is-last="idx === sortedSecrets.length - 1"
          @copy="handleCopy"
          @update:memo="handleUpdateMemo" />
      </ul>
    </div>
  </div>
</template>
