<!-- src/components/layout/ImprovedFooter.vue -->
<!--
  Changes from DefaultFooter:
  - Wider, changing max-w-2xl to max-w-4xl
-->
<script setup lang="ts">
  import { computed } from 'vue';
  import { useRoute } from 'vue-router';
  import FeedbackToggle from '@/components/FeedbackToggle.vue';
  import JurisdictionToggle from '@/components/JurisdictionToggle.vue';
  import LanguageToggle from '@/components/LanguageToggle.vue';
  import FooterLinks from '@/components/layout/FooterLinks.vue';
  import OIcon from '@/components/icons/OIcon.vue';
  import ThemeToggle from '@/components/ThemeToggle.vue';
  import { WindowService } from '@/services/window.service';
  import { useDomainsStore, useMetadataListStore } from '@/stores';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { useI18n } from 'vue-i18n';


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
      fixed bottom-0 left-0 right-0
      bg-white dark:bg-gray-900
      border-t border-gray-200 dark:border-gray-700
      shadow-lg
      z-20
      md:hidden"
    :aria-label="t('mobile-navigation')">
    <div class="flex items-center justify-around py-3 px-2">
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
          class="absolute -top-0.5 -right-0.5 inline-flex items-center justify-center min-w-[18px] h-[18px] px-1
                 rounded-full text-[10px] font-semibold leading-none bg-brand-500 text-white shadow-sm"
          :aria-label="`${item.count} items`">
          {{ item.count > 99 ? '99+' : item.count }}
        </span>
      </router-link>
    </div>
  </nav>

  <!-- Main Footer - Natural flow on mobile, fixed on desktop -->
  <!-- prettier-ignore-attribute class -->
  <footer
    class="
      w-full min-w-[320px]
      bg-gray-100
      py-16 md:py-6
      md:fixed md:bottom-0
      dark:bg-gray-800
      z-10
      pb-20 md:pb-6"
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
          class="flex w-full flex-row flex-wrap items-center justify-center gap-3 md:gap-4 md:w-auto md:justify-end">
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
