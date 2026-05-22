// src/apps/secret/routes/secret.ts

import SecretRevealLayout from '@/apps/secret/layouts/SecretRevealLayout.vue';
import ShowSecretContainer from '@/apps/secret/reveal/ShowSecret.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import type { RouteLocationNormalized, RouteRecordRaw } from 'vue-router';
import { SCOPE_PRESETS } from '@/types/router';

/**
 * Type guard that validates a secret key.
 * @param key - The key to validate
 * @returns true if key is a string matching /^[a-zA-Z0-9]+$/
 */
const validateSecretKey = (key: string | string[]): key is string =>
  typeof key === 'string' && /^[a-zA-Z0-9]+$/.test(key);

/**
 * Checks if the show capability is enabled.
 * The secret view page is gated unless ui.capabilities.show is explicitly
 * disabled. An unset flag (undefined) is treated as enabled, matching
 * the config default of true.
 */
const isShowCapabilityEnabled = (): boolean => {
  const bootstrapStore = useBootstrapStore();
  return bootstrapStore.uiCapabilities?.show !== false;
};

/**
 * Shared route configuration for secret-related routes.
 * Handles validation and type safety for the secretIdentifier parameter.
 *
 * - Validates secretIdentifier format in beforeEnter guard
 * - Checks ui.capabilities.show is not disabled
 * - Redirects to Not Found for invalid keys or disabled capability
 * - Provides typed secretIdentifier prop to components
 */
const withValidatedSecretKey = {
  beforeEnter: (to: RouteLocationNormalized) => {
    const isValid = validateSecretKey(to.params.secretIdentifier);

    if (!isValid) {
      return { name: 'NotFound' };
    }

    // Gate the entire page when show capability is disabled
    if (!isShowCapabilityEnabled()) {
      return { name: 'NotFound' };
    }
  },
  props: (route: RouteLocationNormalized) => ({
    secretIdentifier: route.params.secretIdentifier as string,
  }),
} as const;

/**
 * Routes
 */
const routes: Array<RouteRecordRaw> = [
  {
    path: '/secret/:secretIdentifier',
    name: 'Secret link',
    component: ShowSecretContainer,
    meta: {
      title: 'web.TITLES.secret',
      requiresAuth: false,
      layout: SecretRevealLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayPoweredBy: false,
        displayVersion: false,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
    ...withValidatedSecretKey,
  },
];
export default routes;
