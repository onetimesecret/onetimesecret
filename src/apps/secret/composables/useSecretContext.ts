// src/apps/secret/composables/useSecretContext.ts

import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useProductIdentity } from '@/shared/stores/identityStore';
import { useAuthStore } from '@/shared/stores/authStore';

export type ActorRole = 'CREATOR' | 'AUTH_RECIPIENT' | 'ANON_RECIPIENT';

export interface UIConfig {
  showBurnControl: boolean;
  showMarketingUpsell: boolean;
  headerAction: 'DASHBOARD_LINK' | 'SIGNUP_CTA';
}

export function useSecretContext() {
  const route = useRoute();
  const identity = useProductIdentity();
  const auth = useAuthStore();

  const isAuthenticated = computed(() => auth.isLoggedIn);

  // Determine if viewer is the creator of this specific secret
  const isOwner = computed(() => {
    const creatorId = route.meta?.creatorId as string | undefined;
    return creatorId ? auth.custid === creatorId : false;
  });

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

  const theme = computed(() => {
    return identity.domainStrategy === 'custom'
      ? { mode: 'branded' as const, colors: identity.brand?.primary_color }
      : { mode: 'canonical' as const, colors: null };
  });

  return {
    actorRole,
    uiConfig,
    theme,
    isAuthenticated,
    isOwner,
  };
}
