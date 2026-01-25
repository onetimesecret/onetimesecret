<!-- src/shared/components/layout/BillingLayout.vue -->

<script setup lang="ts">
import { useI18n } from 'vue-i18n';
import OIcon from '@/shared/components/icons/OIcon.vue';
import { computed } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
const { t } = useI18n();

// Get org extid from current route
const orgExtid = computed(() => route.params.extid as string);

interface NavigationItem {
  section: string;
  icon: { collection: string; name: string };
  label: string;
  visible?: () => boolean;
}

const sections: NavigationItem[] = [
  {
    section: 'overview',
    icon: { collection: 'heroicons', name: 'credit-card' },
    label: t('web.billing.overview.title'),
  },
  {
    section: 'plans',
    icon: { collection: 'tabler', name: 'square-letter-s' },
    label: t('web.billing.subscription.title'),
  },
  {
    section: 'invoices',
    icon: { collection: 'heroicons', name: 'document-text' },
    label: t('web.billing.invoices.title'),
  },
];

const visibleSections = computed(() =>
  sections.filter((section) => (section.visible ? section.visible() : true))
);

// Build path with current extid
const getPath = (section: string): string => `/billing/${orgExtid.value}/${section}`;

// Check if section is active based on current route
const isActiveSection = (section: string): boolean => route.path.endsWith(`/${section}`);
</script>

<template>
  <div class="mx-auto max-w-5xl px-4 py-8 sm:px-6 lg:px-8">
    <!-- Page Header -->
    <div class="mb-6">
      <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
        {{ t('web.navigation.billing') }}
      </h1>
      <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
        {{ t('web.billing.manage_subscription_and_billing') }}
      </p>
    </div>

    <!-- Tab Navigation -->
    <nav
      class="-mb-px flex space-x-1 overflow-x-auto border-b border-gray-200 dark:border-gray-700"
      aria-label="Billing navigation">
      <router-link
        v-for="item in visibleSections"
        :key="item.section"
        :to="getPath(item.section)"
        :class="[
          'flex items-center gap-2 whitespace-nowrap border-b-2 px-4 py-3 text-sm font-medium transition-colors',
          isActiveSection(item.section)
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
