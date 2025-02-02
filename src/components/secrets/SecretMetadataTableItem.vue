<script setup lang="ts">
import { type MetadataRecords } from '@/schemas/api';
import { formatRelativeTime } from '@/utils/format'
import { computed } from 'vue';
import { RouterLink } from 'vue-router';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();

interface Props {
  secretMetadata: MetadataRecords;
}

const props = defineProps<Props>();

const linkClass = computed(() => {
  return props.secretMetadata.is_destroyed
    ? 'line-through italic text-gray-400 dark:text-gray-500'
    : 'no-underline';
});

const linkTitle = computed(() => props.secretMetadata.is_destroyed ? t('received') : t('not-received'))
const displayKey = computed(() => {
  return `${props.secretMetadata.shortkey}`;
});

const formattedDate = computed(() =>
  formatRelativeTime(props.secretMetadata.updated)
);
</script>

<template>
  <router-link
    :to="{ name: 'Metadata link', params: { metadataKey: secretMetadata.identifier } }"
    :class="[linkClass, 'transition-colors hover:text-brand-500 dark:hover:text-brand-500']"
    :title="linkTitle">
    {{ displayKey }}
    <span
      v-if="secretMetadata.show_recipients"
      class="text-gray-600 dark:text-gray-400">
      ({{ $t('web.COMMON.sent_to') }} {{ secretMetadata.recipients }})
    </span>
  </router-link>
  <span class="ml-2 text-gray-500 dark:text-gray-400"> - </span>
  <em
    class="italic text-gray-500 dark:text-gray-400"
    :title="secretMetadata.updated.toLocaleString()">
    {{ secretMetadata.is_received ? $t('web.COMMON.word_received') : '' }}
    {{ secretMetadata.is_burned ? $t('web.COMMON.word_burned') : '' }} {{ formattedDate }}
  </em>

  <router-link
    v-if="!secretMetadata.is_destroyed"
    :to="{ name: 'Burn secret', params: { metadataKey: secretMetadata.key } }"
    :class="['ml-2 text-red-500 transition-colors hover:text-red-600',
             'dark:text-red-400 dark:hover:text-red-300']"
    :title="$t('web.COMMON.burn_this_secret')">
    <svg
      xmlns="http://www.w3.org/2000/svg"
      class="inline size-5"
      viewBox="0 0 20 20"
      fill="currentColor"
      width="20"
      height="20">
      <path
        fill-rule="evenodd"
        d="M12.395 2.553a1 1 0 00-1.45-.385c-.345.23-.614.558-.822.88-.214.33-.403.713-.57 1.116-.334.804-.614 1.768-.84 2.734a31.365 31.365 0 00-.613 3.58 2.64 2.64 0 01-.945-1.067c-.328-.68-.398-1.534-.398-2.654A1 1 0 005.05 6.05 6.981 6.981 0 003 11a7 7 0 1011.95-4.95c-.592-.591-.98-.985-1.348-1.467-.363-.476-.724-1.063-1.207-2.03zM12.12 15.12A3 3 0 017 13s.879.5 2.5.5c0-1 .5-4 1.25-4.5.5 1 .786 1.293 1.371 1.879A2.99 2.99 0 0113 13a2.99 2.99 0 01-.879 2.121z"
        clip-rule="evenodd"
      />
    </svg>
  </router-link>
</template>
