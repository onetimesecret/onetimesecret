<!-- src/components/dashboard/DashboardTabNav.vue -->
<script setup lang="ts">
  import { WindowService } from '@/services/window.service';
  import { useDomainsStore, useMetadataListStore } from '@/stores';
  import { computed, onMounted } from 'vue';
  import { useRoute } from 'vue-router';
  import { useI18n } from 'vue-i18n';

  const { t } = useI18n();
  const authenticated = WindowService.get('authenticated');
  const domainsEnabled = WindowService.get('domains_enabled');

  const route = useRoute();

  // TODO: Should be the composables
  const metadataListStore = useMetadataListStore();
  const domainsStore = useDomainsStore();

  // Use computed properties to access counts after they're loaded
  const counts = computed(() => ({
    metadata: metadataListStore.count,
    domains: domainsStore.count,
  }));

  onMounted(() => {
    // console.log('[authed]', counts, authenticated);
    if (authenticated) {
      metadataListStore.refreshRecords(true);
      domainsStore.refreshRecords(true);
    }
  });

  /**
   * Checks if the current route path starts with the specified path.
   * @param path - The path to check against the current route.
   * @returns True if the current route path starts with the specified path, false otherwise.
   */
  const isActiveRoute = (path: string) => route.path.startsWith(path);
</script>

<template>
  <nav
    v-if="authenticated"
    aria-label="$t('dashboard-navigation')"
    class="mb-6 overflow-x-auto bg-gray-50/50 px-4 py-2 dark:bg-gray-800/50">
    <!-- Shadow approach -->
    <ul
      class="mx-auto flex min-w-max max-w-7xl items-center justify-between gap-x-2 font-brand"
      role="menubar">
      <!-- Home -->
      <li
        class="flex-shrink-0"
        role="none">
        <router-link
          to="/dashboard"
          role="menuitem"
          :class="[
            'inline-flex items-center py-2 text-lg transition-colors duration-200',
            isActiveRoute('/dashboard')
              ? 'border-b-2 border-brand-500 font-semibold text-brand-500'
              : 'text-gray-700 hover:text-brand-500 dark:text-gray-300 dark:hover:text-brand-500',
          ]">
          <svg
            aria-hidden="true"
            class="mr-2"
            width="20"
            height="20"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
          </svg>
          {{ $t('web.COMMON.title_home') }}
        </router-link>
      </li>

      <!-- Recent Secrets -->
      <li
        class="flex-shrink-0"
        role="none">
        <router-link
          to="/recent"
          role="menuitem"
          class="group relative flex items-center gap-x-2 whitespace-nowrap py-2 text-lg transition-colors duration-200"
          :class="[
            isActiveRoute('/recent')
              ? 'border-b-2 border-brand-500 font-semibold text-brand-500'
              : 'text-gray-700 hover:text-brand-500 dark:text-gray-300 dark:hover:text-brand-500',
          ]">
          <!-- heroicons/outline/clock -->
          <svg
            aria-hidden="true"
            class="h-5 w-5 flex-shrink-0"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div class="flex min-w-0 items-center gap-x-2">
            <span class="block truncate xs:hidden">
              {{ t('web.COMMON.title_recent_secrets') }}
            </span>
            <span class="hidden truncate xs:block">
              {{ t('web.COMMON.title_recent_secrets') }}
            </span>
            <span
              class="flex-shrink-0 rounded-full bg-gray-100 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-800 dark:text-gray-400"
              :aria-label="t('recent-secrets-count')">
              {{ counts.metadata }}
            </span>
          </div>
        </router-link>
      </li>

      <!-- Custom Domains -->
      <li
        v-if="domainsEnabled"
        class="flex-shrink-0"
        role="none">
        <router-link
          to="/domains"
          role="menuitem"
          class="group relative flex items-center gap-x-2 whitespace-nowrap py-2 text-lg transition-colors duration-200"
          :class="[
            isActiveRoute('/domains')
              ? 'border-b-2 border-brand-500 font-semibold text-brand-500'
              : 'text-gray-700 hover:text-brand-500 dark:text-gray-300 dark:hover:text-brand-500',
          ]">
          <!-- heroicons/outline/globe -->
          <svg
            aria-hidden="true"
            class="size-5"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9" />
          </svg>
          <!-- Simplified nesting structure -->
          <span class="block truncate sm:hidden">{{ t('domains') }}</span>
          <span class="hidden truncate sm:block">{{ t('web.COMMON.custom_domains_title') }}</span>
          <span
            class="flex-shrink-0 rounded-full bg-gray-100 py-0.5 text-xs font-medium text-gray-600 dark:bg-gray-800 dark:text-gray-400"
            :aria-label="t('custom-domains-count')">
            {{ counts.domains }}
          </span>
        </router-link>
      </li>
    </ul>
  </nav>
</template>
