<!-- src/components/layout/ColonelAdminLayout.vue -->

<script setup lang="ts">
import OIcon from '@/components/icons/OIcon.vue';
import { WindowService } from '@/services/window.service';
import { computed } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
// const { t } = useI18n();

const windowProps = WindowService.getMultiple(['domains_enabled', 'authentication']);

interface NavigationItem {
  to: string;
  icon: { collection: string; name: string };
  label: string;
  description?: string;
  badge?: string;
  children?: NavigationItem[];
  visible?: () => boolean;
}

const sections: NavigationItem[] = [
  {
    to: '/colonel',
    icon: { collection: 'material-symbols', name: 'family-home-rounded' },
    label: 'Dashboard',
    description: 'Overview and system health',
  },
  {
    to: '/colonel/users',
    icon: { collection: 'heroicons', name: 'users' },
    label: 'Users',
    description: 'User management',
  },
  {
    to: '/colonel/secrets',
    icon: { collection: 'heroicons', name: 'lock-closed' },
    label: 'Secrets',
    description: 'Secret management',
  },
  {
    to: '/colonel/domains',
    icon: { collection: 'heroicons', name: 'globe-alt' },
    label: 'Custom Domains',
    description: 'Domain management',
    visible: () => windowProps.domains_enabled === true,
  },
  {
    to: '/colonel/system',
    icon: { collection: 'material-symbols', name: 'settings-outline' },
    label: 'System',
    description: 'System configuration',
    children: [
      {
        to: '/colonel/settings',
        icon: { collection: 'heroicons', name: 'cog-6-tooth' },
        label: 'Configuration',
      },
      {
        to: '/colonel/database/maindb',
        icon: { collection: 'heroicons', name: 'circle-stack' },
        label: 'Main Database',
      },
      {
        to: '/colonel/database/authdb',
        icon: { collection: 'heroicons', name: 'key' },
        label: 'Auth Database',
        visible: () => windowProps.authentication?.mode === 'advanced',
      },
    ],
  },
  {
    to: '/colonel/banned-ips',
    icon: { collection: 'heroicons', name: 'shield-exclamation' },
    label: 'Banned IPs',
    description: 'IP ban management',
  },
  {
    to: '/colonel/usage',
    icon: { collection: 'heroicons', name: 'document-chart-bar' },
    label: 'Usage Export',
    description: 'Export usage data',
  },
];

const visibleSections = computed(() =>
  sections
    .filter(section => section.visible ? section.visible() : true)
    .map(section => ({
      ...section,
      children: section.children?.filter(child => child.visible ? child.visible() : true),
    }))
);

const isActiveRoute = (path: string): boolean => route.path === path || route.path.startsWith(path + '/');

const isParentActive = (item: NavigationItem): boolean => {
  if (isActiveRoute(item.to)) return true;
  if (item.children) {
    return item.children.some(child => isActiveRoute(child.to));
  }
  return false;
};
</script>

<template>
  <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6 lg:px-8">
    <div class="mb-8">
      <nav class="mb-4 flex items-center text-sm text-gray-500 dark:text-gray-400">
        <router-link
          to="/colonel"
          class="hover:text-gray-700 dark:hover:text-gray-200">
          Colonel
        </router-link>
        <OIcon
          collection="heroicons"
          name="chevron-right-solid"
          class="mx-2 size-4"
          aria-hidden="true" />
        <span class="text-gray-900 dark:text-white">Administration</span>
      </nav>

      <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
        Admin Panel
      </h1>
      <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
        Manage users, secrets, system configuration, and more
      </p>
    </div>

    <div class="flex flex-col gap-8 md:flex-row">
      <!-- Sidebar Navigation -->
      <aside class="w-full md:w-72 md:shrink-0">
        <nav class="space-y-1" aria-label="Colonel navigation">
          <template v-for="item in visibleSections" :key="item.to">
            <!-- Parent item -->
            <div>
              <router-link
                :to="item.to"
                :class="[
                  'group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                  isParentActive(item)
                    ? 'bg-brand-50 text-brand-700 dark:bg-brand-900/30 dark:text-brand-400'
                    : 'text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-800',
                ]">
                <OIcon
                  :collection="item.icon.collection"
                  :name="item.icon.name"
                  :class="[
                    'size-5 transition-colors',
                    isParentActive(item)
                      ? 'text-brand-600 dark:text-brand-400'
                      : 'text-gray-400 group-hover:text-gray-500 dark:text-gray-500 dark:group-hover:text-gray-400',
                  ]"
                  aria-hidden="true" />
                <span class="flex-1">{{ item.label }}</span>
                <span
                  v-if="item.badge"
                  class="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-700 dark:text-gray-300">
                  {{ item.badge }}
                </span>
              </router-link>

              <!-- Child items -->
              <div
                v-if="item.children && isParentActive(item)"
                class="ml-4 mt-1 space-y-1 border-l-2 border-gray-200 pl-4 dark:border-gray-700">
                <router-link
                  v-for="child in item.children"
                  :key="child.to"
                  :to="child.to"
                  :class="[
                    'group flex items-center gap-2 rounded-lg px-3 py-1.5 text-sm transition-colors',
                    isActiveRoute(child.to)
                      ? 'font-medium text-brand-700 dark:text-brand-400'
                      : 'text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-200',
                  ]">
                  <OIcon
                    :collection="child.icon.collection"
                    :name="child.icon.name"
                    :class="[
                      'size-4',
                      isActiveRoute(child.to)
                        ? 'text-brand-600 dark:text-brand-400'
                        : 'text-gray-400 dark:text-gray-500',
                    ]"
                    aria-hidden="true" />
                  {{ child.label }}
                </router-link>
              </div>
            </div>
          </template>
        </nav>
      </aside>

      <!-- Main Content Area -->
      <main class="min-w-0 flex-1">
        <slot></slot>
      </main>
    </div>
  </div>
</template>
