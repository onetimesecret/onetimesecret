<!-- src/components/layout/SettingsLayout.vue -->

<script setup lang="ts">
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import OIcon from '@/components/icons/OIcon.vue';
import { useOrganizationStore } from '@/stores/organizationStore';
import { WindowService } from '@/services/window.service';

const route = useRoute();
const { t } = useI18n();
const organizationStore = useOrganizationStore();

interface NavigationItem {
  to: string;
  icon: { collection: string; name: string };
  label: string;
  description?: string;
  badge?: string;
  children?: NavigationItem[];
  visible?: () => boolean;
}

const billingEnabled = computed(() => {
  try {
    return WindowService.get('billing_enabled') || false;
  } catch {
    return false;
  }
});
const showOrganizations = computed(() =>
  // Show if billing is enabled AND user has organizations OR can create one
   billingEnabled.value && (organizationStore.hasOrganizations || true)
);

const sections: NavigationItem[] = [
  {
    to: '/account/settings/profile',
    icon: { collection: 'heroicons', name: 'user-solid' },
    label: t('web.settings.profile'),
    description: t('web.settings.profile_settings_description'),
  },
  {
    to: '/account/settings/security',
    icon: { collection: 'heroicons', name: 'shield-check-solid' },
    label: t('web.COMMON.security'),
    description: t('web.settings.security_settings_description'),
    children: [
      {
        to: '/account/settings/security/password',
        icon: { collection: 'heroicons', name: 'lock-closed-solid' },
        label: t('web.auth.change-password.title'),
      },
      {
        to: '/account/settings/security/mfa',
        icon: { collection: 'heroicons', name: 'key-solid' },
        label: t('web.auth.mfa.title'),
      },
      {
        to: '/account/settings/security/sessions',
        icon: { collection: 'heroicons', name: 'computer-desktop-solid' },
        label: t('web.auth.sessions.title'),
      },
      {
        to: '/account/settings/security/recovery-codes',
        icon: { collection: 'heroicons', name: 'document-text-solid' },
        label: t('web.auth.recovery-codes.title'),
      },
    ],
  },
  {
    to: '/account/settings/api',
    icon: { collection: 'heroicons', name: 'code-bracket' },
    label: t('api-key'),
    description: t('web.settings.api.manage_api_keys'),
  },
  {
    to: '/account/settings/organizations',
    icon: { collection: 'heroicons', name: 'building-office-2' },
    label: t('web.organizations.title'),
    description: t('web.organizations.organizations_description'),
    visible: () => showOrganizations.value,
  },
  {
    to: '/account/region',
    icon: { collection: 'heroicons', name: 'globe-alt-solid' },
    label: t('web.account.region'),
    description: t('web.regions.data-sovereignty-title'),
    children: [
      {
        to: '/account/region/current',
        icon: { collection: 'heroicons', name: 'map-pin' },
        label: t('web.regions.your-region'),
      },
      {
        to: '/account/region/available',
        icon: { collection: 'heroicons', name: 'globe-americas-solid' },
        label: t('available-regions'),
      },
      {
        to: '/account/region/why',
        icon: { collection: 'heroicons', name: 'shield-check-solid' },
        label: t('web.regions.why-it-matters'),
      },
    ],
  },
  {
    to: '/account/settings/caution',
    icon: { collection: 'heroicons', name: 'cog-6-tooth-solid' },
    label: t('web.settings.caution.title'),
    description: t('web.settings.caution.description'),
  },
];

const visibleSections = computed(() => sections.filter(section => section.visible ? section.visible() : true));

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
  <div class="mx-auto max-w-[1400px] px-4 py-8 sm:px-6 lg:px-8">
    <div class="mb-8">
      <nav class="mb-4 flex items-center text-sm text-gray-500 dark:text-gray-400">
        <router-link
          to="/account"
          class="hover:text-gray-700 dark:hover:text-gray-200">
          {{ t('your-account') }}
        </router-link>
        <OIcon
          collection="heroicons"
          name="chevron-right-solid"
          class="mx-2 size-4"
          aria-hidden="true" />
        <span class="text-gray-900 dark:text-white">{{ t('web.account.settings') }}</span>
      </nav>

      <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
        {{ t('web.account.settings') }}
      </h1>
      <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
        {{ t('web.settings.manage_your_account_settings_and_preferences') }}
      </p>
    </div>

    <div class="flex flex-col gap-8 lg:flex-row">
      <!-- Sidebar Navigation -->
      <aside class="w-full lg:w-72 lg:shrink-0">
        <nav class="space-y-1" aria-label="Settings navigation">
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
        <slot ></slot>
      </main>
    </div>
  </div>
</template>
