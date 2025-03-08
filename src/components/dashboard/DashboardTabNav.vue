<!-- src/components/dashboard/DashboardTabNav.vue -->

<script setup lang="ts">
import { WindowService } from '@/services/window.service';
import { useDomainsStore, useMetadataListStore } from '@/stores';
import { computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const router = useRouter();
const authenticated = WindowService.get('authenticated');
const domainsEnabled = WindowService.get('domains_enabled');

const route = useRoute();

// Store instances
const metadataListStore = useMetadataListStore();
const domainsStore = useDomainsStore();

// Use computed properties to access counts after they're loaded
const counts = computed(() => ({
  metadata: metadataListStore.count,
  domains: domainsStore.count,
}));

onMounted(() => {
  if (authenticated) {
    metadataListStore.refreshRecords(true);
    domainsStore.refreshRecords(true);
  }
});

/**
 * Checks if the current route path starts with the specified path.
 * @param path - The path to check against the current route.
 * @returns True if the current route path starts with the specified path.
 */
const isActiveRoute = (path: string) => route.path.startsWith(path);

// Tab items definition
const tabs = computed(() => {
  const baseItems = [
    {
      id: 'dashboard',
      path: '/dashboard',
      label: t('web.COMMON.title_home'),
      icon: 'home'
    },
    {
      id: 'recent',
      path: '/recent',
      label: t('web.COMMON.title_recent_secrets'),
      count: counts.value.metadata,
      countLabel: t('recent-secrets-count'),
      icon: 'clock'
    }
  ];

  if (domainsEnabled) {
    baseItems.push({
      id: 'domains',
      path: '/domains',
      label: t('web.COMMON.custom_domains_title'),
      shortLabel: t('domains'),
      count: counts.value.domains,
      countLabel: t('custom-domains-count'),
      icon: 'globe'
    });
  }

  return baseItems;
});

/**
 * Handles keyboard navigation between tabs
 */
const handleKeyDown = (event, tabIndex) => {
  if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') {
    event.preventDefault();

    const direction = event.key === 'ArrowRight' ? 1 : -1;
    const newIndex = (tabIndex + direction + tabs.value.length) % tabs.value.length;

    // Navigate to the tab path
    router.push(tabs.value[newIndex].path);

    // Focus the new tab after navigation
    setTimeout(() => {
      const tabElements = document.querySelectorAll('[role="tab"]');
      if (tabElements[newIndex]) {
        tabElements[newIndex].focus();
      }
    }, 50);
  }
};
</script>

<template>
  <nav
    v-if="authenticated"
    :aria-label="$t('dashboard-navigation')"
    class="mb-6 overflow-x-auto bg-gray-50/50 px-4 py-2 dark:bg-gray-800/50">
    <ul
      role="tablist"
      class="mx-auto flex min-w-max max-w-7xl items-center justify-between gap-x-2 font-brand">
      <li
        v-for="(tab, index) in tabs"
        :key="tab.id"
        class="flex-shrink-0">
        <router-link
          :to="tab.path"
          :id="`tab-${tab.id}`"
          role="tab"
          :aria-selected="isActiveRoute(tab.path)"
          :aria-controls="`panel-${tab.id}`"
          class="flex items-center gap-x-2 py-2 text-lg transition-colors duration-200"
          :class="[
            isActiveRoute(tab.path)
              ? 'border-b-2 border-brand-500 font-semibold text-brand-500'
              : 'text-gray-700 hover:text-brand-500 dark:text-gray-300 dark:hover:text-brand-500',
          ]"
          @keydown="e => handleKeyDown(e, index)">
          <!-- Home tab icon -->
          <svg
            v-if="tab.icon === 'home'"
            aria-hidden="true"
            class="mr-2 h-5 w-5"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
          </svg>

          <!-- Recent tab icon -->
          <svg
            v-else-if="tab.icon === 'clock'"
            aria-hidden="true"
            class="h-5 w-5"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>

          <!-- Domains tab icon -->
          <svg
            v-else-if="tab.icon === 'globe'"
            aria-hidden="true"
            class="h-5 w-5"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9" />
          </svg>

          <!-- Tab with count (Recent and Domains) -->
          <template v-if="tab.count !== undefined">
            <!-- Responsive labels based on screen size -->
            <span v-if="tab.shortLabel" class="block truncate xs:hidden">{{ tab.shortLabel }}</span>
            <span v-else-if="tab.icon !== 'home'" class="block truncate xs:hidden">{{ tab.label }}</span>
            <span class="hidden truncate xs:block">{{ tab.label }}</span>

            <!-- Count badge -->
            <span
              class="ml-1 flex-shrink-0 rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-800 dark:text-gray-400"
              :aria-label="tab.countLabel">
              {{ tab.count }}
            </span>
          </template>

          <!-- Home tab (no count) -->
          <template v-else>
            {{ tab.label }}
          </template>
        </router-link>
      </li>
    </ul>
  </nav>
</template>
