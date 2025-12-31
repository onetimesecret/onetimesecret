<!-- src/apps/workspace/components/settings/SettingsNavigation.vue -->

<script setup lang="ts">
import OIcon from '@/shared/components/icons/OIcon.vue';
import type {
  SettingsNavigationItem,
  SettingsNavigationSection,
} from '@/apps/workspace/config/settings-navigation';
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

const props = defineProps<{
  sections: SettingsNavigationSection[];
}>();

const route = useRoute();
const { t } = useI18n();

const visibleSections = computed(() =>
  props.sections.filter((section) => (section.visible ? section.visible() : true))
);

const getVisibleItems = (items: SettingsNavigationItem[]): SettingsNavigationItem[] =>
  items.filter((item) => (item.visible ? item.visible() : true));

const isActiveRoute = (path: string): boolean =>
  route.path === path || route.path.startsWith(path + '/');

const isParentActive = (item: SettingsNavigationItem): boolean => {
  if (isActiveRoute(item.to)) return true;
  if (item.children) {
    return item.children.some((child) => isActiveRoute(child.to));
  }
  return false;
};
</script>

<template>
  <nav
    class="space-y-6"
    aria-label="Settings navigation">
    <!-- Back to Dashboard link -->
    <router-link
      to="/account"
      class="group flex items-center gap-2 text-sm text-gray-600 transition-colors hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-200">
      <OIcon
        collection="heroicons"
        name="arrow-left"
        class="size-4 transition-transform group-hover:-translate-x-0.5"
        aria-hidden="true" />
      {{ t('web.settings.back_to_dashboard') }}
    </router-link>

    <!-- Sections with headers -->
    <div
      v-for="section in visibleSections"
      :key="section.id"
      class="space-y-1">
      <!-- Section header -->
      <h3
        class="px-3 text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400">
        {{ section.label }}
      </h3>

      <!-- Section items -->
      <template
        v-for="item in getVisibleItems(section.items)"
        :key="item.id">
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
              :key="child.id"
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
    </div>
  </nav>
</template>
