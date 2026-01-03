// src/apps/secret/routes/secret.ts

import SecretRevealLayout from '@/apps/secret/layouts/SecretRevealLayout.vue';
import ShowSecretContainer from '@/apps/secret/reveal/ShowSecret.vue';
import type { RouteLocationNormalized, RouteRecordRaw } from 'vue-router';
import { SCOPE_PRESETS } from '@/types/router';

/**
 * Type guard that validates a metadata key.
 * @param key - The key to validate
 * @returns true if key is a string matching /^[a-zA-Z0-9]+$/
 */
const validateSecretKey = (key: string | string[]): key is string =>
  typeof key === 'string' && /^[a-zA-Z0-9]+$/.test(key);

/**
 * Shared route configuration for metadata-related routes.
 * Handles validation and type safety for the secretIdentifier parameter.
 *
 * - Validates secretIdentifier format in beforeEnter guard
 * - Redirects to Not Found for invalid keys
 * - Provides typed secretIdentifier prop to components
 */
const withValidatedSecretKey = {
  beforeEnter: (to: RouteLocationNormalized) => {
    const isValid = validateSecretKey(to.params.secretIdentifier);

    if (!isValid) {
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
