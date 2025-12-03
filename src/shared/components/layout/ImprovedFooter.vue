<!-- src/shared/components/layout/ImprovedFooter.vue -->

<!--
  Changes from DefaultFooter:
  - Wider, changing max-w-2xl to max-w-4xl
-->
<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import FeedbackToggle from '@/apps/secret/components/support/FeedbackToggle.vue';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import JurisdictionToggle from '@/shared/components/ui/JurisdictionToggle.vue';
  import LanguageToggle from '@/shared/components/ui/LanguageToggle.vue';
  import FooterLinks from '@/shared/components/layout/FooterLinks.vue';
  import ThemeToggle from '@/shared/components/ui/ThemeToggle.vue';
  import { WindowService } from '@/services/window.service';
  import { useDomainsStore, useMetadataListStore } from '@/shared/stores';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed } from 'vue';
  import { useRoute } from 'vue-router';

  withDefaults(defineProps<LayoutProps>(), {
    displayFeedback: true,
    displayFooterLinks: true,
    displayVersion: true,
    displayToggles: true,
    displayPoweredBy: true,
  });

  const { t } = useI18n();
  const route = useRoute();
  const windowProps = WindowService.getMultiple([
    'regions_enabled',
    'regions',
    'authentication',
    'i18n_enabled',
    'ot_version',
    'ui',
  ]);

  const domainsEnabled = WindowService.get('domains_enabled');

  // Store instances for counts
  const metadataListStore = useMetadataListStore();
  const domainsStore = useDomainsStore();

  interface NavItem {
    id: string;
    path: string;
    label: string;
    icon: string;
    count?: number | null;
  }

  // Computed counts (data loaded by parent ImprovedLayout)
  const counts = computed(() => ({
    metadata: metadataListStore.count,
    domains: domainsStore.count,
  }));

  // Mobile navigation items
  const mobileNavItems = computed((): NavItem[] => {
    const items: NavItem[] = [
      {
        id: 'create',
        path: '/',
        label: t('web.COMMON.button_create_secret'),
        icon: 'plus-circle-16-solid',
      },
      {
        id: 'recent',
        path: '/recent',
        label: t('web.LABELS.title_recent_secrets'),
        icon: 'clock',
        count: counts.value.metadata,
      }
    ];

    if (domainsEnabled) {
      items.push({
        id: 'domains',
        path: '/domains',
        label: t('web.COMMON.custom_domains_title'),
        icon: 'globe-alt',
        count: counts.value.domains,
      });
    }

    return items;
  });

  // Check if a route is active
  const isActiveRoute = (path: string): boolean => {
    if (route.path === path) return true;
    if (path === '/' && route.path === '/dashboard') return true;
    if (path === '/account' && route.path.startsWith('/account')) return true;
    return route.path.startsWith(path + '/');
  };
</script>

<template>
  <!-- Mobile Product Navigation - Fixed at bottom on mobile only -->
  <!-- prettier-ignore-attribute class -->
  <nav
    class="
      fixed inset-x-0 bottom-0 z-20
      border-t border-gray-200
      bg-white shadow-lg dark:border-gray-700
      dark:bg-gray-900
      md:hidden"
    :aria-label="t('mobile-navigation')">
    <div class="flex items-center justify-around px-2 py-3">
      <router-link
        v-for="item in mobileNavItems"
        :key="item.id"
        :to="item.path"
        class="relative flex flex-col items-center gap-1 px-3 py-1 transition-colors duration-150"
        :class="[
          isActiveRoute(item.path)
            ? 'text-brand-500'
            : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200'
        ]"
        :aria-label="item.label"
        :aria-current="isActiveRoute(item.path) ? 'page' : undefined">
        <!-- Icon -->
        <OIcon
          collection="heroicons"
          :name="`${item.icon}`"
          class="size-6" />

        <!-- Count badge (if present) -->
        <span
          v-if="item.count !== undefined && item.count !== null && item.count > 0"
          class="absolute -right-0.5 -top-0.5 inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-full
                 bg-brand-500 px-1 text-[10px] font-semibold leading-none text-white shadow-sm"
          :aria-label="t('mobile-nav-item-count', { count: item.count })">
          {{ item.count > 99 ? '99+' : item.count }}
        </span>
      </router-link>
    </div>
  </nav>

  <!-- Main Footer - Natural flow on mobile, fixed on desktop -->
  <!-- prettier-ignore-attribute class -->
  <footer
    class="
      z-10 w-full
      min-w-[320px]
      bg-gray-100 py-16
      pb-20 dark:bg-gray-800
      md:fixed
      md:bottom-0
      md:py-6"
    :aria-label="t('site-footer')">
    <div class="container mx-auto max-w-4xl px-4">
      <!-- Footer Links Section -->
      <FooterLinks v-if="displayFooterLinks" />

      <!-- Existing Footer Content -->
      <!-- prettier-ignore-attribute class -->
      <div
        class="
        flex
        flex-col-reverse items-center
        justify-between
        gap-6 md:flex-row
        md:gap-0"
        :class="
          displayFooterLinks && windowProps.ui?.footer_links?.enabled
            ? 'mt-8 border-t border-gray-200 pt-8 dark:border-gray-700'
            : ''
        ">
        <!-- Version and Powered By -->
        <!-- prettier-ignore-attribute class -->
        <div
          class="
          flex w-full
          flex-wrap items-center justify-center
          gap-x-3
          text-center
          text-xs text-gray-500 dark:text-gray-400 md:w-auto md:justify-start md:text-left">
          <span
            v-if="displayVersion"
            :title="`${t('onetime-secret-literal')} Version`">
            <a
              :href="`https://github.com/onetimesecret/onetimesecret/releases/tag/v${windowProps.ot_version}`"
              :aria-label="t('release-notes')">
              v{{ windowProps.ot_version }}
            </a>
          </span>
          <span
            v-if="displayVersion && displayPoweredBy"
            class="text-gray-400 dark:text-gray-600"
            aria-hidden="true">
            •
          </span>
          <span
            v-if="displayPoweredBy"
            :title="`${t('onetime-secret-literal')} Version`">
            <a
              :href="t('web.COMMON.website_url')"
              target="_blank"
              rel="noopener noreferrer">
              {{ t('web.COMMON.powered_by') }}
              {{ t('onetime-secret-literal') }}
            </a>
          </span>
        </div>

        <!-- Toggles Section -->
        <!-- prettier-ignore-attribute class -->
        <div
          v-if="displayToggles"
          class="flex w-full flex-row flex-wrap items-center justify-center gap-3 md:w-auto md:justify-end md:gap-4">
          <JurisdictionToggle v-if="windowProps.regions_enabled && windowProps.regions" />

          <!-- prettier-ignore-attribute class -->
          <ThemeToggle
            class="text-gray-500 transition-colors duration-200
              hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
            :aria-label="t('toggle-dark-mode')" />

          <LanguageToggle
            v-if="windowProps.i18n_enabled"
            :compact="true"
            max-height="max-h-dvh" />

          <!-- prettier-ignore-attribute class -->
          <FeedbackToggle
            v-if="displayFeedback && windowProps.authentication?.enabled"
            class="text-gray-500 transition-colors duration-200
              hover:text-gray-800 dark:text-gray-400 dark:hover:text-gray-100"
            :aria-label="t('provide-feedback')" />
        </div>
      </div>
    </div>
  </footer>
</template>
