<!-- src/components/colonel/ColonelNavigation.vue -->

<script setup lang="ts">
  import OIcon from '@/components/icons/OIcon.vue';
  import { useColonelNavigation } from '@/composables/useColonelNavigation';

  const { navTabs, isTabActive } = useColonelNavigation();
</script>

<template>
  <div class="mx-auto min-w-[320px] max-w-2xl bg-white shadow-sm dark:bg-gray-800">
    <nav class="flex overflow-x-auto">
      <a
        v-for="tab in navTabs"
        :key="tab.href"
        :href="tab.href"
        class="mx-1 flex items-center border-b-2 border-transparent px-4 py-4 font-brand text-lg font-medium text-gray-700 transition-colors duration-150 first:ml-0 hover:border-brand-500 hover:text-brand-600 focus:border-brand-500 focus:outline-none dark:text-gray-200 dark:hover:border-brand-400 dark:hover:text-brand-400"
        :class="{
          'border-brand-500 text-brand-600 dark:text-brand-400': isTabActive(tab.href),
        }">
        <OIcon
          :collection="tab.icon.collection"
          :name="tab.icon.name"
          class="mr-2 h-5 w-5" />
        {{ tab.name }}
      </a>
    </nav>
  </div>
</template>
