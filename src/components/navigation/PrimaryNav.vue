<!-- src/components/navigation/PrimaryNav.vue -->
<!--
  Primary Navigation Component

  This component provides the main navigation for authenticated users.
  It's designed to be included in the header/masthead and provides
  room for growth without overwhelming the interface.

  Features:
  - Responsive tab navigation
  - Count badges for relevant sections
  - Keyboard navigation support
  - Extensible for future sections
-->

<script setup lang="ts">
import { computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { WindowService } from '@/services/window.service';
import { useDomainsStore, useMetadataListStore } from '@/stores';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();

const authenticated = WindowService.get('authenticated');
const domainsEnabled = WindowService.get('domains_enabled');
const cust = WindowService.get('cust');

// Store instances for counts
const metadataListStore = useMetadataListStore();
const domainsStore = useDomainsStore();

// Navigation item interface
interface NavItem {
  id: string;
  path: string;
  label: string;
  icon?: string;
  count?: number | null;
  badge?: string;
  requiresFeature?: string;
  children?: NavItem[];
}

// Computed counts
const counts = computed(() => ({
  metadata: metadataListStore.count,
  domains: domainsStore.count,
}));

// Load counts on mount
onMounted(() => {
  if (authenticated) {
    metadataListStore.refreshRecords(true);
    domainsStore.refreshRecords(true);
  }
});

// Primary navigation items
const primaryNavItems = computed((): NavItem[] => {
  const items: NavItem[] = [
    {
      id: 'home',
      path: '/dashboard',
      label: t('web.COMMON.title_home'),
      icon: 'home',
    },
    {
      id: 'secrets',
      path: '/recent',
      label: 'Secrets',  // Hardcoded for now
      count: counts.value.metadata,
      icon: 'key',
      children: [
        { id: 'recent', path: '/recent', label: 'Recent' },
        { id: 'shared', path: '/shared', label: 'Shared' },
      ]
    }
  ];

  // Add domains if enabled
  if (domainsEnabled) {
    items.push({
      id: 'domains',
      path: '/domains',
      label: t('web.COMMON.custom_domains_title'),
      count: counts.value.domains,
      icon: 'globe',
    });
  }

  // Add tools section for growth
  // This can be conditionally shown based on user tier or features
  if (cust?.feature_flags?.beta) {
    items.push({
      id: 'tools',
      path: '/tools',
      label: t('web.COMMON.tools'),
      icon: 'cog',
      badge: 'New',
      children: [
        { id: 'api', path: '/tools/api', label: 'API Keys' },
        { id: 'webhooks', path: '/tools/webhooks', label: 'Webhooks' },
      ]
    });
  }

  return items;
});

// Check if a route is active
const isActiveRoute = (path: string): boolean => {
  // Check exact match first
  if (route.path === path) return true;
  // Then check if current route starts with the path (for nested routes)
  return route.path.startsWith(path + '/');
};

// Check if any child route is active
const hasActiveChild = (item: NavItem): boolean => {
  if (!item.children) return false;
  return item.children.some(child => isActiveRoute(child.path));
};

// Handle keyboard navigation
const handleKeyDown = (event: KeyboardEvent, index: number) => {
  const items = primaryNavItems.value;

  if (event.key === 'ArrowRight') {
    event.preventDefault();
    const nextIndex = (index + 1) % items.length;
    router.push(items[nextIndex].path);
  } else if (event.key === 'ArrowLeft') {
    event.preventDefault();
    const prevIndex = index === 0 ? items.length - 1 : index - 1;
    router.push(items[prevIndex].path);
  }
};
</script>

<template>
  <nav
    v-if="authenticated"
    class="primary-navigation border-t border-gray-200 dark:border-gray-700"
    :aria-label="t('primary-navigation')">

    <!-- Navigation container -->
    <div class="flex items-center justify-between">
      <!-- Primary navigation items -->
      <ul
        role="tablist"
        class="flex items-center gap-1">
        <li
          v-for="(item, index) in primaryNavItems"
          :key="item.id">
          <router-link
            :to="item.path"
            role="tab"
            :aria-selected="isActiveRoute(item.path) || hasActiveChild(item)"
            :aria-label="item.label"
            class="group relative flex items-center gap-2 px-3 py-2 text-sm font-medium
                   transition-colors duration-150 rounded-lg
                   hover:bg-gray-100 dark:hover:bg-gray-800"
            :class="[
              isActiveRoute(item.path) || hasActiveChild(item)
                ? 'text-brand-600 dark:text-brand-400'
                : 'text-gray-700 dark:text-gray-300'
            ]"
            @keydown="(e: KeyboardEvent) => handleKeyDown(e, index)">

            <!-- Icon (if provided) -->
            <span
              v-if="item.icon"
              class="size-4"
              :class="[
                isActiveRoute(item.path) || hasActiveChild(item)
                  ? 'text-brand-500'
                  : 'text-gray-400 group-hover:text-gray-500 dark:text-gray-500 dark:group-hover:text-gray-400'
              ]">
              <!-- Add your icon component here based on item.icon -->
              <!-- For now, using placeholder -->
              <span class="text-xs">●</span>
            </span>

            <!-- Label -->
            <span>{{ item.label }}</span>

            <!-- Count badge -->
            <span
              v-if="item.count !== undefined && item.count !== null"
              class="ml-1 inline-flex items-center rounded-full px-2 py-0.5
                     text-xs font-medium"
              :class="[
                isActiveRoute(item.path) || hasActiveChild(item)
                  ? 'bg-brand-100 text-brand-700 dark:bg-brand-900/30 dark:text-brand-400'
                  : 'bg-gray-100 text-gray-600 dark:bg-gray-800 dark:text-gray-400'
              ]">
              {{ item.count }}
            </span>

            <!-- New/Beta badge -->
            <span
              v-if="item.badge"
              class="ml-1 inline-flex items-center rounded-full bg-green-100
                     px-2 py-0.5 text-xs font-medium text-green-700
                     dark:bg-green-900/30 dark:text-green-400">
              {{ item.badge }}
            </span>

            <!-- Active indicator -->
            <span
              v-if="isActiveRoute(item.path) || hasActiveChild(item)"
              class="absolute bottom-0 left-0 right-0 h-0.5 bg-brand-500 rounded-full"
              aria-hidden="true"></span>
          </router-link>
        </li>
      </ul>

      <!-- Future: Quick actions area -->
      <div class="flex items-center gap-2">
        <!-- This area can hold quick action buttons, search, etc. -->
        <!-- For now, keeping it as a placeholder for growth -->
      </div>
    </div>

    <!-- Secondary navigation (contextual, shown based on active primary item) -->
    <div
      v-for="item in primaryNavItems"
      :key="`secondary-${item.id}`"
      v-show="item.children && (isActiveRoute(item.path) || hasActiveChild(item))"
      class="mt-2 border-t border-gray-100 pt-2 dark:border-gray-800">
      <ul class="flex items-center gap-4 text-sm">
        <li
          v-for="child in item.children"
          :key="child.id">
          <router-link
            :to="child.path"
            class="text-gray-600 transition-colors hover:text-brand-600
                   dark:text-gray-400 dark:hover:text-brand-400"
            :class="[
              isActiveRoute(child.path)
                ? 'font-medium text-brand-600 dark:text-brand-400'
                : ''
            ]">
            {{ child.label }}
          </router-link>
        </li>
      </ul>
    </div>
  </nav>
</template>

<style scoped>
.primary-navigation {
  /* Ensure smooth transitions and proper spacing */
  padding-top: 0.75rem;
  padding-bottom: 0.5rem;
}

/* Optional: Add smooth height transition for secondary nav */
.primary-navigation > div {
  transition: all 0.2s ease-in-out;
}
</style>
