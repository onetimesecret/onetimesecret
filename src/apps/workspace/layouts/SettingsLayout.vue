<!-- src/apps/workspace/layouts/SettingsLayout.vue -->

<!--
  Settings Layout for workspace account settings pages.
  Provides horizontal tab navigation + content area.
  NOTE: This component does NOT include header/footer - those come from
  the route's meta.layout (WorkspaceLayout) via App.vue.
-->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { getSettingsNavigationSections } from '@/apps/workspace/config/settings-navigation';
import { computed } from 'vue';
import { useRoute } from 'vue-router';

const { t } = useI18n();
const route = useRoute();

// Flatten navigation sections into tab items
const tabItems = computed(() => {
  const sections = getSettingsNavigationSections(t);
  return sections.flatMap((section) =>
    section.items.filter((item) => (item.visible ? item.visible() : true))
  );
});

// Check if route matches item or any of its children
const isActiveRoute = (item: (typeof tabItems.value)[0]): boolean => {
  if (route.path === item.to || route.path.startsWith(item.to + '/')) return true;
  if (item.children) {
    return item.children.some(
      (child) => route.path === child.to || route.path.startsWith(child.to + '/')
    );
  }
  return false;
};
</script>

<template>
  <div class="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
    <!-- Back to Dashboard -->
    <router-link
      to="/"
      class="group mb-6 inline-flex items-center gap-2 text-sm text-gray-600 transition-colors hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-200">
      <OIcon
        collection="heroicons"
        name="arrow-left"
        class="size-4 transition-transform group-hover:-translate-x-0.5"
        aria-hidden="true" />
      {{ t('web.settings.back_to_dashboard') }}
    </router-link>

    <!-- Page Header -->
    <div class="mb-6">
      <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
        {{ t('web.TITLES.account') }}
      </h1>
      <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
        {{ t('web.settings.manage_your_account_settings_and_preferences') }}
      </p>
    </div>

    <!-- Tab Navigation -->
    <nav
      class="-mb-px flex space-x-1 overflow-x-auto border-b border-gray-200 dark:border-gray-700"
      aria-label="Settings navigation">
      <router-link
        v-for="item in tabItems"
        :key="item.id"
        :to="item.to"
        :class="[
          'flex items-center gap-2 whitespace-nowrap border-b-2 px-4 py-3 text-sm font-medium transition-colors',
          isActiveRoute(item)
            ? 'border-brand-500 text-brand-600 dark:border-brand-400 dark:text-brand-400'
            : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 dark:text-gray-400 dark:hover:border-gray-600 dark:hover:text-gray-300',
        ]">
        <OIcon
          :collection="item.icon.collection"
          :name="item.icon.name"
          class="size-4"
          aria-hidden="true" />
        {{ item.label }}
      </router-link>
    </nav>

    <!-- Main Content Area -->
    <main class="pt-6">
      <slot></slot>
    </main>
  </div>
</template>
