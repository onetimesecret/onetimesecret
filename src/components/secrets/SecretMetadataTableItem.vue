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
  view?: 'default' | 'table-cell';
}

const props = defineProps<Props>();

// Default to 'default' view if not specified
const viewMode = computed(() => props.view || 'default');

const linkClass = computed(() => {
  const baseClass = 'transition-colors focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2';
  const stateClass = props.secretMetadata.is_destroyed
    ? 'line-through italic text-gray-400 dark:text-gray-500'
    : 'text-gray-800 dark:text-gray-200 hover:text-brand-500 dark:hover:text-brand-400';

  return [baseClass, stateClass];
});

const linkTitle = computed(() => props.secretMetadata.is_destroyed
  ? t('web.STATUS.expired')
  : props.secretMetadata.is_received
    ? t('web.COMMON.received')
    : t('web.LABELS.pending')
);

const displayKey = computed(() => {
  return `${props.secretMetadata.secret_shortkey}`;
});

const formattedDate = computed(() =>
  formatRelativeTime(props.secretMetadata.updated)
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
  <!-- Table Cell View -->
  <div v-if="viewMode === 'table-cell'" class="flex items-center space-x-2">
    <!-- Status Icon -->
    <OIcon
      collection="heroicons"
      :name="statusIcon"
      size="4"
      aria-hidden="true" />

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

  <!-- Default View (Backward Compatible) -->
  <div v-else class="flex flex-wrap items-center gap-2">
    <router-link
      :to="{ name: 'Receipt link', params: { metadataKey: secretMetadata.identifier } }"
      :class="linkClass"
      :title="linkTitle">
      <span class="flex items-center gap-1.5">
        <OIcon
          collection="heroicons"
          :name="statusIcon"
          size="4"
          aria-hidden="true" />
        <span class="font-mono">{{ displayKey }}</span>
      </span>
    </router-link>

    <span
      v-if="secretMetadata.show_recipients"
      class="text-sm text-gray-600 dark:text-gray-400">
      ({{ $t('web.COMMON.sent_to') }} {{ secretMetadata.recipients }})
    </span>

    <span class="text-gray-400 dark:text-gray-600">•</span>

    <span
      class="text-sm italic text-gray-500 dark:text-gray-400"
      :title="secretMetadata.updated.toLocaleString()">
      <span v-if="secretMetadata.is_received" class="">
        {{ $t('web.STATUS.received') }}
      </span>
      <span v-if="secretMetadata.is_burned" class="">
        {{ $t('web.STATUS.burned') }}
      </span>
      <span>{{ formattedDate }}</span>
    </span>

    <router-link
      v-if="!secretMetadata.is_destroyed"
      :to="{ name: 'Burn secret', params: { metadataKey: secretMetadata.key } }"
      class="ml-auto rounded-md bg-red-100 p-1 text-red-600 transition-colors hover:bg-red-200
        focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2
        dark:bg-red-900/20 dark:text-red-400 dark:hover:bg-red-800/30"
      :title="$t('web.COMMON.burn_this_secret')"
      :aria-label="$t('web.COMMON.burn_this_secret')">
      <OIcon
        collection="heroicons"
        name="fire"
        class="size-4"
        aria-hidden="true" />
    </router-link>
  </div>
</template>
