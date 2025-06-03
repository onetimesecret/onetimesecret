// src/composables/useColonelNavigation.ts

import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';

export interface ColonelNavTab {
  name: string;
  href: string;
  icon: { collection: string; name: string };
}

/**
 * Provides Colonel navigation tabs and utilities
 */
export function useColonelNavigation() {
  const { t } = useI18n();
  const route = useRoute();

  // Main Colonel navigation tabs
  const navTabs = computed((): ColonelNavTab[] => [
    {
      name: t('web.COMMON.title_home'),
      href: '/colonel',
      icon: { collection: 'material-symbols', name: 'family-home-rounded' },
    },
    {
      name: t('web.colonel.activity'),
      href: '/colonel/info',
      icon: { collection: 'ph', name: 'activity' },
    },
    // {
    //   name: t('web.colonel.users'),
    //   href: '/colonel/users',
    //   icon: { collection: 'heroicons', name: 'user-solid' },
    // },
    {
      name: t('web.colonel.settings'),
      href: '/colonel/settings',
      icon: { collection: 'material-symbols', name: 'settings' },
    },
  ]);

  // Current active tab based on route
  const activeTab = computed(() => {
    const currentPath = route.path;
    return navTabs.value.find((tab) => tab.href === currentPath);
  });

  // Check if a specific tab is active
  const isTabActive = (href: string): boolean => route.path === href;

  return {
    navTabs,
    activeTab,
    isTabActive,
  };
}
