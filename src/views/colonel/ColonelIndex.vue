<script setup lang="ts">
import { useColonelStore } from '@/stores/colonelStore';
import { onMounted } from 'vue';
import { storeToRefs } from 'pinia';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();

const tabs = [
  { name: t('Home'), href: '/colonel' },
  { name: t('stats'), href: '/colonel/info#stats' },
  { name: t('customers'), href: '/colonel/info#customers' },
  { name: t('feedback'), href: '/colonel/info#feedback' },
  { name: t('misc'), href: '/colonel/info#misc' },
];

const store = useColonelStore();
const { isLoading } = storeToRefs(store);
const { fetch } = store; // Actions are extracted directly

onMounted(fetch);
</script>

<template>
  <div class="overflow-hidden rounded-lg bg-white shadow-lg dark:bg-gray-800">
    <div
      id="primaryTabs"
      class="sticky top-0 z-10 border-b border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-800">
      <nav class="flex overflow-x-auto">
        <a
          v-for="tab in tabs"
          :key="tab.href"
          :href="tab.href"
          class="px-3 py-2 text-sm font-medium text-gray-600 hover:text-brand-500 dark:text-gray-300 dark:hover:text-brand-400">
          {{ tab.name }}
        </a>
      </nav>
    </div>

    <div v-if="isLoading">Loading...</div>

    <div v-else class="p-6">

      plop
    </div>
  </div>
</template>
