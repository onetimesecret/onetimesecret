<!-- src/App.vue -->
<script setup lang="ts">
import QuietLayout from '@/layouts/QuietLayout.vue';
import type { LayoutProps } from '@/types/ui/layouts';
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import StatusBar from './components/StatusBar.vue';

const { locale } = useI18n();
const route = useRoute();

const defaultProps: LayoutProps = {
  displayMasthead: true,
  displayNavigation: true,
  displayLinks: true,
  displayFeedback: true,
  displayVersion: true,
  displayPoweredBy: true,
  displayToggles: true,
};

// Bring the layout and route together
const layout = computed(() => { return route.meta.layout || QuietLayout });
const layoutProps = computed(() => ({
  ...defaultProps,
  ...(route.meta.layoutProps ?? {})
}));
</script>
<!--
/**
 * Root application component managing layouts and routing.
 *
 * Security Note:
 * - No keep-alive to prevent caching of sensitive data
 * - Components force re-creation via :key binding
 * - Each route gets fresh component instance
 *
 * Routing Strategy:
 * - Dynamic layout selection via route.meta.layout
 * - Full component reset on navigation using :key="$route.fullPath"
 * - Layout remains stable while route components update
 *
 * @see /src/router/index.ts for route definitions
 * @see /src/layouts for available layouts
 */
-->
<template>
  <!-- Dynamic layout selection based on route.meta.layout -->
  <component :is="layout"
             :lang="locale"
             v-bind="layoutProps">
    <!-- Router view with forced component recreation on route changes -->
    <router-view v-slot="{ Component }" class="rounded-md">
      <component :is="Component" :key="$route.fullPath" />
    </router-view>

    <StatusBar position="bottom" />
  </component>
</template>
