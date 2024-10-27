<!-- JurisdictionList.vue -->
<template>
  <ul
    class="divide-y divide-gray-100 dark:divide-gray-700 rounded-lg border border-gray-200 dark:border-gray-700"
    role="list"
  >
    <li
      v-for="jurisdiction in jurisdictions"
      :key="jurisdiction.identifier"
      class="flex items-center gap-3 p-3 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
    >
      <Icon
        :icon="jurisdiction.icon"
        class="h-5 w-5 flex-shrink-0 text-gray-400 dark:text-gray-500"
        aria-hidden="true"
      />

      <a
        :href="`https://${jurisdiction.domain}/signup`"
        :class="{ 'font-medium': isCurrentJurisdiction(jurisdiction) }"
        class="flex-grow text-gray-700 dark:text-gray-200 hover:text-brand-600 dark:hover:text-brand-400 text-sm"
      >
        {{ jurisdiction.display_name }}
      </a>

      <span
        v-if="isCurrentJurisdiction(jurisdiction)"
        class="inline-flex items-center rounded-full bg-brand-50 dark:bg-brand-900/20 px-2 py-1 text-xs font-medium text-brand-700 dark:text-brand-300"
        aria-label="Current jurisdiction"
      >
        Current
      </span>
    </li>
  </ul>
</template>

<script setup lang="ts">
import { Icon } from '@iconify/vue';
import type { Jurisdiction } from '@/types/onetime';

const props = defineProps<{
  jurisdictions: Jurisdiction[];
  currentJurisdiction: Jurisdiction;
}>();

const isCurrentJurisdiction = (jurisdiction: Jurisdiction) =>
  jurisdiction.identifier === props.currentJurisdiction.identifier;
</script>
