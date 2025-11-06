<!-- src/components/navigation/ImprovedPrimaryNav.vue -->
<!--
  Improved Primary Navigation Component

  Key improvements:
  - Horizontal tab layout inspired by GitHub
  - Better use of horizontal space
  - Quick actions area for future features
  - Cleaner visual hierarchy
  - Room for growth without clutter
-->

<script setup lang="ts">
import { computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { WindowService } from '@/services/window.service';
import { useDomainsStore, useMetadataListStore } from '@/stores';
import OIcon from '@/components/icons/OIcon.vue';

const { t } = useI18n();
const route = useRoute();

const domainsEnabled = WindowService.get('domains_enabled');

// Store instances for counts
const metadataListStore = useMetadataListStore();
const domainsStore = useDomainsStore();

interface NavItem {
  id: string;
  path: string;
  label: string;
  icon?: string;
  count?: number | null;
  countLabel?: string;
  shortLabel?: string;
  requiresAuth?: boolean;
}

// Computed counts
const counts = computed(() => ({
  metadata: metadataListStore.count,
  domains: domainsStore.count,
}));

// Load counts on mount
onMounted(() => {
  metadataListStore.refreshRecords(true);
  if (domainsEnabled) {
    domainsStore.refreshRecords(true);
  }
});

// Primary navigation items - now more prominent
const primaryNavItems = computed((): NavItem[] => {
  const items: NavItem[] = [
    {
      id: 'dashboard',
      path: '/dashboard',
      label: t('web.COMMON.title_home'),
      icon: 'home',
    },
    {
      id: 'recent',
      path: '/recent',
      label: t('web.LABELS.title_recent_secrets'),
      count: counts.value.metadata,
      countLabel: t('recent-secrets-count'),
      icon: 'clock',
    }
  ];

  // Add domains if enabled
  if (domainsEnabled) {
    items.push({
      id: 'domains',
      path: '/domains',
      label: t('web.COMMON.custom_domains_title'),
      shortLabel: t('domains'),
      count: counts.value.domains,
      countLabel: t('custom-domains-count'),
      icon: 'globe',
    });
  }

  return items;
});

// Quick action buttons
const quickActions = computed(() => [
  {
    id: 'create',
    label: t('web.LABELS.create_new_secret'),
    path: '/',
    variant: 'primary',
    icon: 'plus',
  }
]);

// Check if a route is active
const isActiveRoute = (path: string): boolean => {
  if (route.path === path) return true;
  // Special case for account/settings paths
  if (path === '/account' && route.path.startsWith('/account')) return true;
  return route.path.startsWith(path + '/');
};
</script>

<template>
  <nav
    class="flex items-center justify-between py-0"
    :aria-label="t('main-navigation')">

    <!-- Primary tabs -->
    <div class="flex items-center -mb-px">
      <router-link
        v-for="item in primaryNavItems"
        :key="item.id"
        :to="item.path"
        class="group relative flex items-center font-brand gap-2 px-3 py-3 text-base font-medium
               border-b-2 transition-all duration-150"
        :class="[
          isActiveRoute(item.path)
            ? 'border-brand-500 text-gray-900 dark:text-white'
            : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 dark:text-gray-400 dark:hover:text-gray-200'
        ]">

        <!-- Icon -->
        <OIcon
          v-if="item.icon"
          collection="heroicons"
          :name="`${item.icon}`"
          class="size-4"
          :class="[
            isActiveRoute(item.path)
              ? 'text-brand-500'
              : 'text-gray-400 group-hover:text-gray-500'
          ]" />

        <!-- Label -->
        <span>{{ item.label }}</span>

        <!-- Count badge -->
        <span
          v-if="item.count !== undefined && item.count !== null && item.count > 0"
          class="inline-flex items-center justify-center min-w-[20px] h-5 px-1.5
                 rounded-full text-xs font-medium"
          :class="[
            isActiveRoute(item.path)
              ? 'bg-brand-100 text-brand-700 dark:bg-brand-900/30 dark:text-brand-400'
              : 'bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400'
          ]"
          :aria-label="item.countLabel">
          {{ item.count }}
        </span>
      </router-link>
    </div>

    <!-- Quick actions -->
    <div class="flex items-center gap-3">
      <!-- Create Secret Button -->
      <router-link
        v-for="action in quickActions"
        :key="action.id"
        :to="action.path"
        class="inline-flex items-center font-brand gap-2 px-4 py-2 text-base font-medium
               rounded-lg transition-all duration-150"
        :class="[
          action.variant === 'primary'
            ? 'bg-brand-500 text-white hover:bg-brand-600 dark:bg-brand-600 dark:hover:bg-brand-700'
            : 'bg-gray-100 text-gray-700 hover:bg-gray-200 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700'
        ]">
        <OIcon
          v-if="action.icon"
          collection="heroicons"
          :name="`${action.icon}-solid`"
          class="size-4" />
        <span>{{ action.label }}</span>
      </router-link>

      <!-- Future: Search bar could go here -->
      <!-- <div class="relative">
        <input
          type="search"
          placeholder="Search secrets..."
          class="pl-9 pr-3 py-2 text-sm border border-gray-300 rounded-lg
                 focus:outline-none focus:ring-2 focus:ring-brand-500"
        />
        <OIcon
          collection="heroicons"
          name="magnifying-glass-outline"
          class="absolute left-3 top-2.5 size-4 text-gray-400" />
      </div> -->
    </div>
  </nav>
</template>

<style scoped>
/* Ensure smooth transitions */
nav a {
  position: relative;
}

/* Optional: Add a subtle shadow to the active tab */
nav a.router-link-active::after {
  content: '';
  position: absolute;
  bottom: -1px;
  left: 0;
  right: 0;
  height: 2px;
  background: currentColor;
}
</style>
