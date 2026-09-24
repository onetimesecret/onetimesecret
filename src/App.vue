<!-- src/App.vue -->

<script setup lang="ts">
  import { useI18n } from 'vue-i18n';
  import StaleSessionNotice from '@/shared/components/auth/StaleSessionNotice.vue';
  import VerificationUnavailable from '@/shared/components/auth/VerificationUnavailable.vue';
  import { iconLibraryComponents } from '@/shared/components/icons/sprites';
  import CriticalSprites from '@/shared/components/icons/sprites/CriticalSprites.vue';
  import ImpersonationBanner from '@/shared/components/ui/ImpersonationBanner.vue';
  import { NotificationHost } from '@/shared/components/ui/notifications';
  import RouteErrorBoundary from '@/shared/components/errors/RouteErrorBoundary.vue';
  import QuietLayout from '@/shared/layouts/MinimalLayout.vue';
  import { useBrandTheme } from '@/shared/composables/useBrandTheme';
  import { useAuthStore } from '@/shared/stores/authStore';
  import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
  import { useNotificationsStore } from '@/shared/stores/notificationsStore';
  import { consumeSessionTransition } from '@/utils/sessionTransition';
  import type { LayoutProps } from '@/types/ui/layouts';
  import { computed, ref, onMounted, watchEffect, type Component, markRaw } from 'vue';
  import { useRoute } from 'vue-router';

  const { locale, t } = useI18n();
  const route = useRoute();
  const bootstrapStore = useBootstrapStore();
  const authStore = useAuthStore();

  // Protected content is withheld while authority cannot be established
  // (#4460): `unavailable` after repeated failed verifications, or a `checking`
  // that was never resolved. `mfa_pending` is also withheld here
  // (ADR-046#authority-action-gating): a refresh can flip an already-mounted protected route from
  // authenticated to mfa_pending WITHOUT starting a new navigation, so the
  // MFA guard is not rerun and the previously-rendered subtree would keep
  // showing account data while stores are reset. /mfa-verify itself has
  // `requiresAuth: false`, so it stays reachable. The guards let navigation
  // through in these states so nobody is bounced to /signin by an outage;
  // this is where the protected UI is actually kept off the screen. One
  // place, so it holds for every layout of both bundles. Public routes
  // render as usual.
  const withholdProtected = computed(
    () =>
      !!route.meta.requiresAuth &&
      (authStore.authStatus === 'unavailable' ||
        authStore.authStatus === 'checking' ||
        authStore.authStatus === 'mfa_pending')
  );

  // One session transition, one message (#4461). A session that ended or was
  // replaced outside this tab ends in a forced page load; the page that loads
  // next (this one) says why, once. consume removes the parked kind, so a
  // remount or a later navigation cannot repeat it.
  const announceSessionTransition = () => {
    const kind = consumeSessionTransition();
    if (!kind) return;
    useNotificationsStore().show(t(`web.auth.session.${kind}`), 'info', 'top', 10000);
  };

  useBrandTheme();

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
    displayGlobalBroadcast: true, // will only display if one exists
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
  onMounted(announceSessionTransition);
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
  <!-- Impersonation notice. Mounted HERE, outside the layout, because it must
       appear on every route of both bundles: AdminLayout does not compose
       BaseLayout, so a layout-level mount (the PreviewModeBanner pattern) would
       miss whole surfaces. Gated on the server-derived bootstrap block, so it
       is absent for every ordinary session. -->
  <ImpersonationBanner v-if="bootstrapStore.impersonation" />

  <!-- Stale-session state (ADR-046 "Forced page load"). Mounted here for the
       same reason: every route of both bundles. It renders only while the
       refresh coordinator holds that state, i.e. after a forced reload was
       cancelled or bounded. -->
  <StaleSessionNotice />

  <!-- Dynamic layout selection based on route.meta.layout -->
  <component
    :is="layout"
    :lang="locale"
    v-bind="layoutProps">
    <!-- Router view with forced component recreation on route changes.
         RouteErrorBoundary swaps a thrown route subtree for a visible error
         panel so a render/setup failure never leaves a silent blank page
         (the global errorHandler only logs). Keyed + reset on route change. -->
    <router-view
      v-slot="{ Component }"
      class="rounded-md">
      <RouteErrorBoundary :reset-key="$route.fullPath">
        <VerificationUnavailable v-if="withholdProtected" />
        <component
          v-else
          :is="Component"
          :key="$route.fullPath" />
      </RouteErrorBoundary>
    </router-view>

    <NotificationHost />

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
