<!-- src/App.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import { iconLibraryComponents } from '@/shared/components/icons/sprites';
  import CriticalSprites from '@/shared/components/icons/sprites/CriticalSprites.vue';
  import { SubtleProgress } from '@/shared/components/ui/notifications';
  import QuietLayout from '@/shared/layouts/MinimalLayout.vue';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed, ref, onMounted, watchEffect, type Component, markRaw } from 'vue';
  import { useRoute } from 'vue-router';

  const { locale } = useI18n();
  const route = useRoute();

  // Cross-layout safety net merged before route.meta.layoutProps. Each
  // layout should own true defaults for every boolean prop it consumes
  // (Vue coerces missing Boolean props to `false`, and an explicit
  // `false` bypasses the child's withDefaults). The DEV check below
  // warns if any layout receives an incomplete props object.
  const defaultProps: LayoutProps = {
    displayMasthead: true,
    displayNavigation: true,
    displayPrimaryNav: false, // opt-in per layout (e.g. WorkspaceLayout)
    displayHeader: true,
    displayFooterLinks: true,
    displayFeedback: true,
    displayVersion: true,
    displayPoweredBy: false, // used in only a few places
    displayToggles: true,
    displayGlobalBroadcast: true, // will only display if one exists (need to restart backend when changes)
  };

  // List of boolean keys every layout is expected to receive. Kept in
  // sync with LayoutProps booleans.
  const EXPECTED_LAYOUT_BOOLEANS = [
    'displayGlobalBroadcast',
    'displayHeader',
    'displayMasthead',
    'displayNavigation',
    'displayPrimaryNav',
    'displayFooterLinks',
    'displayFeedback',
    'displayVersion',
    'displayPoweredBy',
    'displayToggles',
  ] as const;

  // Bring the layout and route together
  const layout = computed(() => route.meta.layout || QuietLayout);
  const layoutProps = computed(() => ({
    ...defaultProps,
    ...(route.meta.layoutProps ?? {}),
  }));

  // Dev-only guard against the silent-hidden-chrome bug class. If the
  // merged props object lacks any expected boolean key, the target
  // layout must default it locally; otherwise Vue coerces undefined to
  // `false` and chrome silently disappears.
  if (import.meta.env.DEV) {
    watchEffect(() => {
      const merged = layoutProps.value as Record<string, unknown>;
      const missing = EXPECTED_LAYOUT_BOOLEANS.filter((k) => !(k in merged));
      if (missing.length > 0) {
        const layoutName =
          (layout.value as { __name?: string; name?: string })?.__name ??
          (layout.value as { __name?: string; name?: string })?.name ??
          'unknown';
        console.warn(
          `[LayoutProps] Route "${String(route.name)}" → layout "${layoutName}" ` +
            `received an incomplete props object (missing: ${missing.join(', ')}). ` +
            `Vue will coerce missing Boolean props to \`false\` unless the layout ` +
            `defaults them in withDefaults. See src/App.vue defaultProps.`
        );
      }
    });
  }

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

    <SubtleProgress />

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
