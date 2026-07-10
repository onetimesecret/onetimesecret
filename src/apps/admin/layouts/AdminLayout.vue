<!-- src/apps/admin/layouts/AdminLayout.vue -->

<script setup lang="ts">
  import OIcon from '@/shared/components/icons/OIcon.vue';
  import { useTheme } from '@/shared/composables/useTheme';
  import { useProductIdentity } from '@/shared/stores/identityStore';
  import { isColorValue } from '@/utils/color-utils';
  import { computed, onMounted } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRoute } from 'vue-router';

  import { CONSOLE_GROUPS, CONSOLE_SECTIONS } from '../console-sections';

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

  // Watch-tower accent strip, driven by the same brand-identity machinery the
  // main site's BaseLayout uses: the resolved brand primary is either a Tailwind
  // class token or a raw colour value, so branch the same way. Falls back to the
  // brand complement (brandcomp) when the identity store yields nothing.
  const identityStore = useProductIdentity();
  const accentColorClass = computed(() => {
    const currentColor = identityStore.primaryColor;
    if (isColorValue(currentColor)) return '';
    return currentColor || 'bg-brandcomp-500';
  });
  const accentColorStyle = computed(() => {
    const currentColor = identityStore.primaryColor;
    return isColorValue(currentColor) ? { backgroundColor: currentColor } : {};
  });

  /** Sections bucketed into their rail bands, in {@link CONSOLE_GROUPS} order. */
  const navBands = computed(() =>
    CONSOLE_GROUPS.map((band) => ({
      ...band,
      sections: CONSOLE_SECTIONS.filter((s) => s.group === band.key),
    })).filter((band) => band.sections.length > 0)
  );
</script>

<!--
  Persistent-sidebar shell for the rebuilt Colonel admin console — "the
  operations ledger". The chrome commits to an institutional, document-like
  identity: a slab-serif structural voice (page titles, rail band eyebrows),
  hairline rules over drop shadows, and a current-line marker (left accent bar)
  for the active nav row. It is intentionally self-contained — it does NOT
  compose the customer ManagementHeader/BaseLayout — so the admin bundle stays
  isolated.
-->
<template>
  <div class="flex min-h-screen bg-gray-50 text-gray-900 dark:bg-gray-950 dark:text-gray-100">
    <!-- All along the watch tower: the same fixed accent strip the main site
         wears, driven by the shared brand-identity machinery so the console
         reads as part of the product. -->
    <div
      class="fixed top-0 left-0 z-50 h-1 w-full"
      :class="accentColorClass"
      :style="accentColorStyle"></div>

    <!-- Persistent left navigation rail -->
    <aside
      class="hidden w-64 shrink-0 flex-col border-r border-gray-200 bg-white md:flex dark:border-gray-800 dark:bg-gray-900">
      <!-- Header record: the escape hatch and the console lock-up share one
           bordered block so the back link reads as a deliberate eyebrow rather
           than a stray line pushing the mark down. The heavy bottom rule closes
           the record. Full navigation (not a router-link): the console is an
           isolated bundle. Neutral copy — no product name — to respect the
           tenant's applied branding. -->
      <div class="border-b-2 border-gray-900 dark:border-gray-100">
        <a
          href="/"
          class="flex items-center gap-1.5 px-5 pt-3 pb-2 text-xs font-medium text-gray-400 transition-colors hover:text-gray-700 dark:text-gray-500 dark:hover:text-gray-200"
          data-testid="admin-back-to-site">
          <OIcon
            collection="heroicons"
            name="arrow-left"
            size="4" />
          {{ t('web.colonel.backToSite') }}
        </a>

        <!-- Masthead: a proper lock-up, not just an icon + word. -->
        <div class="flex items-center gap-3 px-5 pt-1 pb-4">
          <span
            class="flex size-9 shrink-0 items-center justify-center rounded-md bg-brand-600 text-white shadow-sm dark:bg-brand-500">
            <OIcon
              collection="heroicons"
              name="shield-check"
              size="5" />
          </span>
          <span class="flex flex-col leading-none">
            <span class="font-brand text-lg font-bold tracking-tight">{{ t('web.colonel.admin') }}</span>
            <span
              class="mt-1 font-brand text-[10px] font-semibold tracking-[0.2em] text-gray-400 uppercase dark:text-gray-500">
              {{ t('web.colonel.nav.consoleTag') }}
            </span>
          </span>
        </div>
      </div>

      <nav
        class="flex-1 overflow-y-auto px-3 pb-4"
        :aria-label="t('web.colonel.admin')">
        <template
          v-for="band in navBands"
          :key="band.key">
          <!-- Rail band eyebrow: slab-serif, tracked — encodes the console's
               real structure (identity / security / platform / billing). Bands
               that hold a single item carry no labelKey and render headerless
               (Overview pinned top, broadcast lever floating bottom). -->
          <p
            v-if="band.labelKey"
            class="px-3 pt-5 pb-1 font-brand text-[11px] font-semibold tracking-[0.15em] text-gray-400 uppercase first:pt-4 dark:text-gray-500">
            {{ t(band.labelKey) }}
          </p>
          <div
            v-else
            class="pt-4"></div>

          <div class="space-y-0.5">
            <router-link
              v-for="section in band.sections"
              :key="section.key"
              :to="section.to!"
              class="group relative flex items-center gap-3 border-l-2 py-2 pr-2 pl-3 text-sm font-medium transition-colors"
              :class="
                route.path === section.to
                  ? 'border-brand-600 bg-brand-50 text-brand-700 dark:border-brand-400 dark:bg-brand-500/10 dark:text-brand-200'
                  : 'border-transparent text-gray-600 hover:border-gray-300 hover:bg-gray-50 hover:text-gray-900 dark:text-gray-400 dark:hover:border-gray-700 dark:hover:bg-gray-800/60 dark:hover:text-gray-100'
              ">
              <OIcon
                collection="heroicons"
                :name="section.icon"
                size="5"
                :class="
                  route.path === section.to
                    ? 'text-brand-600 dark:text-brand-400'
                    : 'text-gray-400 group-hover:text-gray-500 dark:text-gray-500 dark:group-hover:text-gray-400'
                " />
              <span class="truncate">{{ t(section.labelKey) }}</span>
            </router-link>
          </div>
        </template>
      </nav>
    </aside>

    <!-- Main column -->
    <div class="flex min-w-0 flex-1 flex-col">
      <header
        class="flex h-16 items-center justify-between border-b border-gray-200 bg-white/80 px-5 backdrop-blur-sm sm:px-8 dark:border-gray-800 dark:bg-gray-900/80">
        <!-- Breadcrumb, not a page title: the bold page heading lives in each
             view's body. This is muted wayfinding + a persistent home link, so
             it no longer echoes the body <h2>. -->
        <nav
          class="flex min-w-0 items-center gap-1.5 text-sm"
          :aria-label="t('web.colonel.admin')">
          <router-link
            to="/colonel"
            class="shrink-0 rounded font-brand font-semibold tracking-wider text-gray-400 uppercase hover:text-gray-600 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-500 dark:hover:text-gray-300">
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
          class="inline-flex size-9 items-center justify-center rounded-md text-gray-500 transition-colors hover:bg-gray-100 focus:ring-2 focus:ring-brand-500 focus:outline-none dark:text-gray-400 dark:hover:bg-gray-800"
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

      <main class="flex-1 overflow-x-auto p-5 sm:p-8">
        <slot></slot>
      </main>
    </div>
  </div>
</template>
