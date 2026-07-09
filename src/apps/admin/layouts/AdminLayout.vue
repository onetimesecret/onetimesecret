<!-- src/apps/admin/layouts/AdminLayout.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useTheme } from '@/shared/composables/useTheme';
  import { onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRoute } from 'vue-router';

  import { CONSOLE_SECTIONS } from '../console-sections';

  // App.vue passes the customer chrome layout props via v-bind; this console
  // owns its own chrome, so drop those attrs instead of letting them fall
  // through onto the root element.
  defineOptions({ inheritAttrs: false });

  const { t } = useI18n();
  const route = useRoute();
  const { isDarkMode, toggleDarkMode, initializeTheme } = useTheme();

  // Sync the reactive flag with the class the inline head script already
  // applied before mount, so the toggle button reflects the real state.
  onMounted(initializeTheme);
</script>

<!--
  Persistent-sidebar shell for the rebuilt Colonel admin console.

  Unlike the legacy ColonelAdminLayout (a centered container navigated only via
  dashboard quick-actions), a console needs a navigable map that is always in
  view. This layout is intentionally self-contained — it does NOT compose the
  customer ManagementHeader/BaseLayout — so the admin bundle stays isolated.
-->
<template>
  <div class="flex min-h-screen bg-gray-50 text-gray-900 dark:bg-gray-900 dark:text-gray-100">
    <!-- Persistent left navigation rail -->
    <aside
      class="hidden w-64 shrink-0 flex-col border-r border-gray-200 bg-white md:flex dark:border-gray-800 dark:bg-gray-950">
      <div class="flex h-14 items-center gap-2 border-b border-gray-200 px-4 dark:border-gray-800">
        <OIcon
          collection="heroicons"
          name="shield-check"
          class="text-brand-600 dark:text-brand-400"
          size="6" />
        <span class="font-brand text-lg font-semibold">{{ t('web.colonel.admin') }}</span>
      </div>

      <nav
        class="flex-1 space-y-1 overflow-y-auto p-3"
        :aria-label="t('web.colonel.admin')">
        <template
          v-for="section in CONSOLE_SECTIONS"
          :key="section.key">
          <!-- Live section: a real route link. -->
          <router-link
            v-if="section.to"
            :to="section.to"
            class="flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors"
            :class="
              route.path === section.to
                ? 'bg-brand-50 text-brand-700 dark:bg-brand-900/30 dark:text-brand-300'
                : 'text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-800'
            ">
            <OIcon
              collection="heroicons"
              :name="section.icon"
              size="5" />
            {{ t(section.labelKey) }}
          </router-link>

          <!-- Placeholder section: dimmed, non-interactive until a later phase
               wires its route. Communicates the console map without dead links. -->
          <span
            v-else
            class="flex cursor-not-allowed items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-gray-400 dark:text-gray-600"
            aria-disabled="true">
            <OIcon
              collection="heroicons"
              :name="section.icon"
              size="5" />
            {{ t(section.labelKey) }}
          </span>
        </template>
      </nav>

      <!-- Escape hatch: the console is an isolated bundle, so this is a full
           navigation back to the main site (not a router-link). Pinned to the
           foot of the rail so it never scrolls out of reach. -->
      <div class="border-t border-gray-200 p-3 dark:border-gray-800">
        <a
          href="/"
          class="flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-700 dark:text-gray-400 dark:hover:bg-gray-800 dark:hover:text-gray-200"
          data-testid="admin-back-to-site">
          <OIcon
            collection="heroicons"
            name="arrow-left"
            size="5" />
          {{ t('web.colonel.backToSite') }}
        </a>
      </div>
    </aside>

    <!-- Main column -->
    <div class="flex min-w-0 flex-1 flex-col">
      <header
        class="flex h-14 items-center justify-between border-b border-gray-200 bg-white px-4 dark:border-gray-800 dark:bg-gray-950">
        <!-- Breadcrumb, not a page title: the bold page heading lives in each
             view's body. This is muted wayfinding + a persistent home link, so
             it no longer echoes the body <h2>. -->
        <nav
          class="flex min-w-0 items-center gap-1 text-sm"
          :aria-label="t('web.colonel.admin')">
          <router-link
            to="/colonel"
            class="shrink-0 rounded text-gray-500 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-brand-500 dark:text-gray-400 dark:hover:text-gray-200">
            {{ t('web.colonel.admin') }}
          </router-link>
          <template v-if="route.meta.title && route.path !== '/colonel'">
            <OIcon
              collection="heroicons"
              name="chevron-right"
              size="4"
              class="shrink-0 text-gray-300 dark:text-gray-600"
              aria-hidden="true" />
            <span
              class="truncate font-medium text-gray-900 dark:text-white"
              aria-current="page">
              {{ t(route.meta.title as string) }}
            </span>
          </template>
        </nav>
        <button
          type="button"
          class="inline-flex size-9 items-center justify-center rounded-md text-gray-500 hover:bg-gray-100 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-400 dark:hover:bg-gray-800"
          :aria-label="t('web.layout.toggle_dark_mode')"
          :aria-pressed="isDarkMode"
          @click="toggleDarkMode">
          <OIcon
            collection="heroicons"
            name="light-bulb"
            :class="isDarkMode ? 'text-brand-400' : ''"
            size="5" />
        </button>
      </header>

      <main class="flex-1 overflow-x-auto p-4 sm:p-6">
        <slot></slot>
      </main>
    </div>
  </div>
</template>
