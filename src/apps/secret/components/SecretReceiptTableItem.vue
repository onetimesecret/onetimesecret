<!-- src/apps/secret/components/SecretReceiptTableItem.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { type ReceiptRecords } from '@/schemas/api/account/endpoints/recent';
import { formatRelativeTime } from '@/utils/format'
import { computed } from 'vue';
import { RouterLink } from 'vue-router';
const { t } = useI18n();

interface Props {
  secretReceipt: ReceiptRecords;
}

const props = defineProps<Props>();

const linkClass = computed(() => {
  const baseClass = 'transition-colors focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2';
  const stateClass = props.secretReceipt.is_destroyed
    ? 'line-through italic text-gray-400 dark:text-gray-500'
    : 'text-gray-800 dark:text-gray-200 hover:text-brand-500 dark:hover:text-brand-400';

  return [baseClass, stateClass];
});

const linkTitle = computed(() => {
  if (props.secretReceipt.is_destroyed) {
    return t('web.STATUS.expired');
  }
  if (props.secretReceipt.is_received) {
    return t('web.COMMON.received');
  }
  return '';
}
);

const displayIdentifier = computed(() => props.secretReceipt.secret_shortid ?? '\u2014');

const formattedDate = computed(() =>
  formatRelativeTime(props.secretReceipt.created)
);

// Compute status icon based on secret state
const statusIcon = computed(() => {
  if (props.secretReceipt.is_destroyed) return 'x-mark';
  if (props.secretReceipt.is_burned) return 'fire';
  if (props.secretReceipt.is_received) return 'check';
  return 'lock-closed-16-solid';
});

</script>

<template>
  <div class="flex items-center space-x-2">
    <!-- Status Icon -->
    <OIcon
      collection="heroicons"
      :name="statusIcon"
      size="4"
      aria-hidden="true" />

    <!-- Secret Key with Date below -->
    <div class="flex flex-col">
      <!-- Secret Key with Link -->
      <router-link
        :to="{ name: 'Receipt link', params: { receiptIdentifier: secretReceipt.identifier } }"
        :class="linkClass"
        :title="linkTitle"
        :aria-label="`${t('web.COMMON.secret')} ${displayIdentifier} ${linkTitle}`">
        <span class="font-mono text-sm font-medium">{{ displayIdentifier }}</span>
      </router-link>

      <!-- Date Information -->
      <span
        class="text-xs text-gray-500 dark:text-gray-400"
        :title="secretReceipt.updated.toLocaleString()">
        {{ formattedDate }}
      </span>
    </div>
  </div>

  <!-- Default View (Backward Compatible) -->
</template>
