// src/apps/secret/routes/metadata.ts

import SecretLayout from '@/apps/secret/layouts/SecretLayout.vue';
import { WindowService } from '@/services/window.service';
import BurnSecret from '@/apps/secret/reveal/BurnSecret.vue';
import ShowMetadata from '@/apps/secret/reveal/ShowMetadata.vue';
import type { RouteLocationNormalized, RouteRecordRaw } from 'vue-router';
import { SCOPE_PRESETS } from '@/types/router';

/**
 * Type guard that validates a metadata key.
 * @param key - The key to validate
 * @returns true if key is a string matching /^[a-zA-Z0-9]+$/
 */
const validateMetadataKey = (key: string | string[]): key is string =>
  typeof key === 'string' && /^[a-zA-Z0-9]+$/.test(key);

/**
 * Shared route configuration for metadata-related routes.
 * Handles validation and type safety for the metadataIdentifier parameter.
 *
 * - Validates metadataIdentifier format in beforeEnter guard
 * - Redirects to Not Found for invalid keys
 * - Provides typed metadataIdentifier prop to components
 */
const withValidatedMetadataKey = {
  beforeEnter: (to: RouteLocationNormalized) => {
    // Use window service directly rather than the identity store
    // since the routes start before the pinia stores.
    const domainStrategy = WindowService.get('domain_strategy') as string;

    if (domainStrategy === 'custom') {
      to.meta.layoutProps = {
        ...to.meta.layoutProps,
        displayMasthead: true,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayPoweredBy: true,
        displayToggles: true,
      };
    }

    const isValid = validateMetadataKey(to.params.metadataIdentifier);
    if (!isValid) {
      return { name: 'NotFound' };
    }
  },
  props: (route: RouteLocationNormalized) => ({
    metadataIdentifier: route.params.metadataIdentifier as string,
  }),
} as const;

/**
 * Routes for viewing and managing metadata/secrets:
 * - /private/:metadataIdentifier - View metadata and secret details
 * - /receipt/:metadataIdentifier - Alternative path for viewing metadata and secret details
 * - /private/:metadataIdentifier/burn - Permanently delete a secret
 * - /receipt/:metadataIdentifier/burn - Alternative path for permanently deleting a secret
 */
const routes: Array<RouteRecordRaw> = [
  {
    path: '/private/:metadataIdentifier',
    name: 'Metadata link',
    component: ShowMetadata,
    ...withValidatedMetadataKey,
    meta: {
      title: 'web.TITLES.metadata',
      layout: SecretLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
        displayVersion: true,
        displayToggles: true,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/receipt/:metadataIdentifier',
    name: 'Receipt link',
    component: ShowMetadata,
    ...withValidatedMetadataKey,
    meta: {
      title: 'web.TITLES.receipt',
      layout: SecretLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
        displayVersion: true,
        displayToggles: true,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/private/:metadataIdentifier/burn',
    name: 'Burn secret',
    component: BurnSecret,
    ...withValidatedMetadataKey,
    meta: {
      title: 'web.TITLES.burn_secret',
      layout: SecretLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayPoweredBy: true,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/receipt/:metadataIdentifier/burn',
    name: 'Burn receipt',
    component: BurnSecret,
    ...withValidatedMetadataKey,
    meta: {
      title: 'web.TITLES.burn_secret',
      layout: SecretLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayPoweredBy: true,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
];

export default routes;
