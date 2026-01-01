<!-- src/apps/workspace/layouts/SettingsLayout.vue -->

<!--
  Settings Layout for workspace account settings pages.
  Provides sidebar navigation + content area.
  NOTE: This component does NOT include header/footer - those come from
  the route's meta.layout (WorkspaceLayout) via App.vue.
-->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import SettingsNavigation from '@/apps/workspace/components/settings/SettingsNavigation.vue';
import SettingsPageHeader from '@/apps/workspace/components/settings/SettingsPageHeader.vue';
import { getSettingsNavigationSections } from '@/apps/workspace/config/settings-navigation';
import { computed } from 'vue';

const { t } = useI18n();

// Navigation sections from config
const navigationSections = computed(() => getSettingsNavigationSections(t));
</script>

<template>
  <div class="mx-auto max-w-[1400px] px-4 py-8 sm:px-6 lg:px-8">
    <!-- Page Header -->
    <SettingsPageHeader />

    <!-- Settings Layout: Sidebar + Content -->
    <div class="flex flex-col gap-8 md:flex-row">
      <!-- Sidebar Navigation -->
      <aside class="w-full md:w-72 md:shrink-0">
        <SettingsNavigation :sections="navigationSections" />
      </aside>

      <!-- Main Content Area -->
      <main class="min-w-0 flex-1">
        <slot ></slot>
      </main>
    </div>
  </div>
</template>
