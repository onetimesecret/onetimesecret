<script setup lang="ts">
import type { Jurisdiction } from '@/schemas/models';
import OIcon from '@/components/icons/OIcon.vue';

const props = defineProps<{
  jurisdictions: Jurisdiction[];
  currentJurisdiction?: Jurisdiction | null;
}>();

const isCurrentJurisdiction = (jurisdiction: Jurisdiction) =>
  jurisdiction.identifier === props.currentJurisdiction?.identifier;
</script>

<template>
  <ul
    class="divide-y divide-gray-100 rounded-lg border border-gray-200 dark:divide-gray-700 dark:border-gray-700"
    role="list">
    <li
      v-for="jurisdiction in jurisdictions"
      :key="jurisdiction.identifier"
      class="flex flex-wrap items-center gap-3 p-3 transition-colors hover:bg-gray-50 dark:hover:bg-gray-800 sm:flex-nowrap sm:p-4">
      <div class="flex w-full items-center gap-3 sm:w-auto">
        <OIcon
          :collection="jurisdiction.icon.collection"
          :name="jurisdiction.icon.name"
          class="size-5 shrink-0 text-gray-400 dark:text-gray-500"
          aria-hidden="true"
        />

        <a
          :href="`https://${jurisdiction.domain}/signup`"
          :class="{ 'font-medium': isCurrentJurisdiction(jurisdiction) }"
          class="grow text-sm text-gray-700 hover:text-brand-600 dark:text-gray-200 dark:hover:text-brand-400"
          :aria-current="isCurrentJurisdiction(jurisdiction) ? 'true' : undefined"
          :aria-label="$t('jurisdiction-display_name-iscurrentjurisdiction-', [jurisdiction.display_name, isCurrentJurisdiction(jurisdiction) ? `(Current)` : ``])">
          {{ jurisdiction.display_name }}
        </a>
      </div>

      <span
        v-if="isCurrentJurisdiction(jurisdiction)"
        class="ml-auto inline-flex items-center rounded-full bg-brand-50 px-2 py-1 text-xs font-medium text-brand-700 dark:bg-brand-900/20 dark:text-brand-300"
        aria-hidden="true">
        {{ $t('current') }}
      </span>
    </li>
  </ul>
</template>
