// src/apps/secret/composables/useSecretContext.ts

import { computed, toValue, type MaybeRefOrGetter } from 'vue';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { useAuthStore } from '@/shared/stores/authStore';

export type ActorRole = 'CREATOR' | 'RECIPIENT_AUTH' | 'RECIPIENT_ANON';

export interface UIConfig {
  showBurnControl: boolean;
  showEntitlementsUpgrade: boolean;
  headerAction: 'DASHBOARD_LINK' | 'SIGNUP_CTA';
  /**
   * Whether to show creator-specific alerts (warnings/notices).
   * The composable owns "who sees creator alerts" (role-based).
   * The component owns "which alert variant" (state-based, e.g., pre/post reveal).
   */
  showCreatorAlerts: boolean;
}

export interface SecretContextOptions {
  /**
   * Whether the current user owns this secret.
   * Pass from API response (details.is_owner) for accurate ownership detection.
   */
  isOwner?: MaybeRefOrGetter<boolean>;
}

/**
 * Provides actor-based UI configuration for secret viewing.
 *
 * Determines what UI elements to show based on who is viewing:
 * - CREATOR: Owner viewing their own secret (can burn, sees dashboard link)
 * - RECIPIENT_AUTH: Logged-in user viewing someone else's secret
 * - RECIPIENT_ANON: Anonymous viewer (sees entitlements upgrade, signup CTA)
 *
 * @example
 * // In a component with access to secret details:
 * const { uiConfig } = useSecretContext({ isOwner: () => details.is_owner });
 *
 * // Then use uiConfig for conditional rendering:
 * // v-if="uiConfig.showBurnControl"
 * // v-if="uiConfig.showEntitlementsUpgrade"
 */
export function useSecretContext(options: SecretContextOptions = {}) {
  const identity = useProductIdentity();
  const auth = useAuthStore();

  const isAuthenticated = computed(() => auth.isAuthenticated === true);

  // Ownership from API response (details.is_owner) is the source of truth
  const isOwner = computed(() => toValue(options.isOwner) ?? false);

  const actorRole = computed<ActorRole>(() => {
    if (isOwner.value) return 'CREATOR';
    if (isAuthenticated.value) return 'RECIPIENT_AUTH';
    return 'RECIPIENT_ANON';
  });

  const uiConfig = computed<UIConfig>(() => {
    switch (actorRole.value) {
      case 'CREATOR':
        return {
          showBurnControl: true,
          showEntitlementsUpgrade: false,
          headerAction: 'DASHBOARD_LINK',
          showCreatorAlerts: true,
        };
      case 'RECIPIENT_AUTH':
        return {
          showBurnControl: false,
          showEntitlementsUpgrade: false,
          headerAction: 'DASHBOARD_LINK',
          showCreatorAlerts: false,
        };
      case 'RECIPIENT_ANON':
      default:
        return {
          showBurnControl: false,
          showEntitlementsUpgrade: true,
          headerAction: 'SIGNUP_CTA',
          showCreatorAlerts: false,
        };
    }
  });

  const theme = computed(() =>
    identity.domainStrategy === 'custom'
      ? { mode: 'branded' as const, colors: identity.brand?.primary_color }
      : { mode: 'canonical' as const, colors: null }
  );

  return {
    actorRole,
    uiConfig,
    theme,
    isAuthenticated,
    isOwner,
  };
}
