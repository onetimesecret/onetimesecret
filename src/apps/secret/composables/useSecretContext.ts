// src/apps/secret/composables/useSecretContext.ts

import { computed, toValue, type MaybeRefOrGetter } from 'vue';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { useAuthStore } from '@/shared/stores/authStore';

export type ActorRole = 'CREATOR' | 'AUTH_RECIPIENT' | 'ANON_RECIPIENT';

export interface UIConfig {
  showBurnControl: boolean;
  showMarketingUpsell: boolean;
  headerAction: 'DASHBOARD_LINK' | 'SIGNUP_CTA';
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
 * - AUTH_RECIPIENT: Logged-in user viewing someone else's secret
 * - ANON_RECIPIENT: Anonymous viewer (sees marketing upsell, signup CTA)
 *
 * @example
 * // In a component with access to secret details:
 * const { uiConfig } = useSecretContext({ isOwner: () => details.is_owner });
 *
 * // Then use uiConfig for conditional rendering:
 * // v-if="uiConfig.showBurnControl"
 * // v-if="uiConfig.showMarketingUpsell"
 */
export function useSecretContext(options: SecretContextOptions = {}) {
  const identity = useProductIdentity();
  const auth = useAuthStore();

  const isAuthenticated = computed(() => auth.isAuthenticated === true);

  // Ownership from API response (details.is_owner) is the source of truth
  const isOwner = computed(() => toValue(options.isOwner) ?? false);

  const actorRole = computed<ActorRole>(() => {
    if (isOwner.value) return 'CREATOR';
    if (isAuthenticated.value) return 'AUTH_RECIPIENT';
    return 'ANON_RECIPIENT';
  });

  const uiConfig = computed<UIConfig>(() => {
    switch (actorRole.value) {
      case 'CREATOR':
        return {
          showBurnControl: true,
          showMarketingUpsell: false,
          headerAction: 'DASHBOARD_LINK',
        };
      case 'AUTH_RECIPIENT':
        return {
          showBurnControl: false,
          showMarketingUpsell: false,
          headerAction: 'DASHBOARD_LINK',
        };
      case 'ANON_RECIPIENT':
      default:
        return {
          showBurnControl: false,
          showMarketingUpsell: true,
          headerAction: 'SIGNUP_CTA',
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
