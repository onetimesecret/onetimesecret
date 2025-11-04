<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { type MetadataRecords } from '@/schemas/api';
import { formatRelativeTime } from '@/utils/format'
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { RouterLink } from 'vue-router';
const { t } = useI18n();

interface Props {
  secretMetadata: MetadataRecords;
}

const props = defineProps<Props>();

const linkClass = computed(() => {
  const baseClass = 'transition-colors focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2';
  const stateClass = props.secretMetadata.is_destroyed
    ? 'line-through italic text-gray-400 dark:text-gray-500'
    : 'text-gray-800 dark:text-gray-200 hover:text-brand-500 dark:hover:text-brand-400';

  return [baseClass, stateClass];
});

const linkTitle = computed(() => {
  if (props.secretMetadata.is_destroyed) {
    return t('web.STATUS.expired');
  }
  if (props.secretMetadata.is_received) {
    return t('web.COMMON.received');
  }
  return '';
}
);

const displayKey = computed(() => `${props.secretMetadata.secret_shortid}`);

const formattedDate = computed(() =>
  formatRelativeTime(props.secretMetadata.created)
);

// Compute status icon based on secret state
const statusIcon = computed(() => {
  if (props.secretMetadata.is_destroyed) return 'x-mark';
  if (props.secretMetadata.is_burned) return 'fire';
  if (props.secretMetadata.is_received) return 'check';
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
        :to="{ name: 'Receipt link', params: { metadataKey: secretMetadata.identifier } }"
        :class="linkClass"
        :title="linkTitle"
        :aria-label="`${$t('web.COMMON.secret')} ${displayKey} ${linkTitle}`">
        <span class="font-mono text-sm font-medium">{{ displayKey }}</span>
      </router-link>

      <!-- Date Information -->
      <span
        class="text-xs text-gray-500 dark:text-gray-400"
        :title="secretMetadata.updated.toLocaleString()">
        {{ formattedDate }}
      </span>
    </div>
  </div>

  <!-- Default View (Backward Compatible) -->

</template>
