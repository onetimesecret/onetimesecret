<!-- src/apps/workspace/components/layout/WorkspaceFooter.vue -->

<!--
  Simplified footer for authenticated workspace users.
  Based on ManagementFooter with:
  - Removed: Region selector, color mode toggle, language toggle
  - Added: Standard SaaS footer links (API Docs, Branding Guide, Feedback)
-->
<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useDomainsStore, useReceiptListStore } from '@/shared/stores';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { isExternalUrl } from '@/utils/url';
  import { storeToRefs } from 'pinia';
  import { computed } from 'vue';
  import { useRoute } from 'vue-router';

  withDefaults(defineProps<LayoutProps>(), {
    displayFooterLinks: true,
    displayVersion: true,
    displayToggles: false,
    displayPoweredBy: true,
  });

  const { t, locale } = useI18n();
  const route = useRoute();
  const bootstrapStore = useBootstrapStore();
  const { ot_version, ot_version_long, domains_enabled, support_host, ui } = storeToRefs(bootstrapStore);

  // Store instances for counts
  const receiptListStore = useReceiptListStore();
  const domainsStore = useDomainsStore();

  interface NavItem {
    id: string;
    path: string;
    label: string;
    icon: string;
    count?: number | null;
  }

  interface FooterLink {
    label: string;
    href: string;
  }

  // Computed counts (data loaded by parent layout)
  const counts = computed(() => ({
    receipts: receiptListStore.count,
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
        count: counts.value.receipts,
      },
    ];

    if (domains_enabled.value) {
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

  // Workspace footer links — configurable via ui.workspace_links
  // Falls back to computed URLs based on support_host when not configured
  const docsBase = computed(() => {
    const host = support_host.value;
    return host ? `https://${host}` : '';
  });

  const docsLocale = computed(() => {
    const lang = locale.value;
    return lang?.split(/[-_]/)[0] || 'en';
  });

  // Default links when no workspace_links are configured
  const defaultLinks: { i18nKey: string; href: () => string }[] = [
    {
      i18nKey: 'web.footer.api_docs',
      href: () => `${docsBase.value}/${docsLocale.value}/rest-api/`,
    },
    {
      i18nKey: 'web.footer.branding_guide',
      href: () => `${docsBase.value}/${docsLocale.value}/custom-domains/brand-guide/`,
    },
    {
      i18nKey: 'web.TITLES.feedback',
      href: () => '/feedback',
    },
  ];

  const workspaceLinksEnabled = computed(() => ui.value?.workspace_links?.enabled ?? true);

  const footerLinks = computed((): FooterLink[] => {
    if (!workspaceLinksEnabled.value) {
      return [];
    }
    const links = ui.value?.workspace_links?.links;
    if (links?.length) {
      return links
        .filter(link => link.url?.trim())
        .map((link) => ({
          label: link.i18n_key ? t(link.i18n_key) : (link.text || ''),
          href: link.url!,
        }));
    }
    // Fallback to computed defaults
    return defaultLinks.map(def => ({
      label: t(def.i18nKey),
      href: def.href(),
    }));
  });

  // Check if a route is active
  const isActiveRoute = (path: string): boolean => {
    if (route.path === path) return true;
    if (path === '/' && route.path === '/dashboard') return true;
    if (path === '/account' && route.path.startsWith('/account')) return true;
    // /domains redirects to /org/:orgid/domains — match the resolved path
    if (path === '/domains' && /^\/org\/[^/]+\/domains(\/|$)/.test(route.path)) return true;
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
    :aria-label="t('web.layout.mobile_navigation')">
    <div class="flex items-center justify-around px-2 py-3">
      <router-link
        v-for="item in mobileNavItems"
        :key="item.id"
        :to="item.path"
        class="relative flex flex-col items-center gap-1 px-3 py-1 transition-colors duration-150"
        :class="[
          isActiveRoute(item.path)
            ? 'text-brand-500'
            : 'text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200',
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
          class="bg-brand-500 absolute -top-0.5 -right-0.5 inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-full px-1 text-[10px] leading-none font-semibold text-white shadow-sm"
          :aria-label="t('web.layout.mobile_nav_item_count', { count: item.count })">
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
      dark:bg-gray-800
      md:fixed
      md:bottom-0
      md:py-6"
    :aria-label="t('web.layout.site_footer')">
    <div class="container mx-auto max-w-4xl px-4">
      <!-- Footer Links Section -->
      <div
        v-if="displayFooterLinks && ui?.footer_links?.enabled !== false"
        class="mb-6 flex flex-wrap items-center justify-center gap-x-6 gap-y-2">
        <template
          v-for="link in footerLinks"
          :key="link.href">
          <a
            :href="link.href"
            :target="isExternalUrl(link.href) ? '_blank' : '_self'"
            :rel="isExternalUrl(link.href) ? 'noopener noreferrer' : undefined"
            class="text-sm text-gray-600 transition-colors duration-200 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100">
            {{ link.label }}
          </a>
        </template>
      </div>

      <!-- Version and Powered By -->
      <!-- prettier-ignore-attribute class -->
      <div
        class="
        flex
        flex-col items-center
        justify-center
        gap-2 text-center
        text-xs text-gray-500 dark:text-gray-400">
        <div class="flex items-center gap-x-3">
          <span
            v-if="displayVersion"
            :title="`${t('web.homepage.onetime_secret_literal')} ${t('web.COMMON.version')}`">
            <a
              :href="`https://github.com/onetimesecret/onetimesecret/releases/tag/v${ot_version}`"
              target="_blank"
              rel="noopener noreferrer"
              :aria-label="t('web.layout.release_notes')">
              v{{ ot_version_long }}
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
            :title="`${t('web.homepage.onetime_secret_literal')} ${t('web.COMMON.version')}`">
            <a
              :href="t('web.COMMON.website_url')"
              target="_blank"
              rel="noopener noreferrer">
              {{ t('web.COMMON.powered_by') }}
              {{ t('web.homepage.onetime_secret_literal') }}
            </a>
          </span>
        </div>
      </div>
    </div>
  </footer>
</template>
