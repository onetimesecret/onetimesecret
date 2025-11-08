<!-- src/App.vue -->

<script setup lang="ts">
  import StatusBar from '@/components/StatusBar.vue';
  import QuietLayout from '@/layouts/QuietLayout.vue';
  import CriticalSprites from '@/components/icons/sprites/CriticalSprites.vue';
  import { iconLibraryComponents } from '@/components/icons/sprites';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed, ref, onMounted, type Component, markRaw } from 'vue';
  import { useI18n } from 'vue-i18n';
  import { useRoute } from 'vue-router';

  const { locale } = useI18n();
  const route = useRoute();

  const defaultProps: LayoutProps = {
    displayMasthead: true,
    displayNavigation: true,
    displayFooterLinks: true,
    displayFeedback: true,
    displayVersion: true,
    displayPoweredBy: false, // used in only a few places
    displayToggles: true,
    displayGlobalBroadcast: true, // will only display if one exists (need to restart backend when changes)
  };

  // Bring the layout and route together
  const layout = computed(() => route.meta.layout || QuietLayout);
  const layoutProps = computed(() => ({
    ...defaultProps,
    ...(route.meta.layoutProps ?? {}),
  }));

  // Dynamic sprite management
  const loadedSprites = ref<Record<string, Component>>({});

  /**
   * Load all icon sprite components on app initialization
   * Uses dynamic imports for code splitting while ensuring sprites are available globally
   */
  const loadAllSprites = async () => {
    try {
      const loadPromises = Object.entries(iconLibraryComponents).map(async ([key, loader]) => {
        const module = await loader();
        return [key, module.default] as const;
      });

      const results = await Promise.all(loadPromises);
      results.forEach(([key, component]) => {
        loadedSprites.value[key] = markRaw(component);
      });
    } catch (error) {
      console.warn('Failed to load some sprite components:', error);
    }
  };

  onMounted(loadAllSprites);
</script>
<!--
/**
 * Root application component managing layouts and routing.
 *
 * Security Note: we avoid Vue keep-alive components to force re-creating them
 * and ensure each route receives a fresh component instance.
 *
 * Routing Strategy Explained:
 * - Dynamically selects layout based on current route metadata
 * - Ensures each navigation creates a fresh component instance
 * - Maintains consistent layout while updating page content
 *
 * @see /src/router/index.ts for route definitions
 * @see /src/layouts for available layouts
 */
-->
<template>
  <!-- Dynamic layout selection based on route.meta.layout -->
  <component
    :is="layout"
    :lang="locale"
    v-bind="layoutProps">
    <!-- Router view with forced component recreation on route changes -->
    <router-view
      v-slot="{ Component }"
      class="rounded-md">
      <component
        :is="Component"
        :key="$route.fullPath" />
    </router-view>

    <StatusBar position="bottom" />

    <!-- Sprite rendering: critical immediately + others dynamically -->
    <div
      id="sprites"
      class="hidden">
      <!-- Critical sprites - immediately available -->
      <CriticalSprites />

      <!-- Other sprites - loaded after initial render -->
      <component
        v-for="(spriteComponent, key) in loadedSprites"
        :key="key"
        :is="spriteComponent" />
    </div>
  </component>
</template>
