import DefaultLayout from '@/layouts/DefaultLayout.vue';
import BurnSecret from '@/views/secrets/BurnSecret.vue';
import ShowMetadata from '@/views/secrets/ShowMetadata.vue';
import { RouteLocationNormalized, RouteRecordRaw } from 'vue-router';

/**
 * Type guard that validates a metadata key.
 * @param key - The key to validate
 * @returns true if key is a string matching /^[a-zA-Z0-9]+$/
 */
const validateMetadataKey = (key: string | string[]): key is string =>
  typeof key === 'string' && /^[a-zA-Z0-9]+$/.test(key);

/**
 * Shared route configuration for metadata-related routes.
 * Handles validation and type safety for the metadataKey parameter.
 *
 * - Validates metadataKey format in beforeEnter guard
 * - Redirects to Not Found for invalid keys
 * - Provides typed metadataKey prop to components
 */
const withValidatedMetadataKey = {
  beforeEnter: (to: RouteLocationNormalized) => {
    const isValid = validateMetadataKey(to.params.metadataKey);
    if (!isValid) {
      return { name: 'Not Found' };
    }
  },
  props: (route: RouteLocationNormalized) => ({
    metadataKey: route.params.metadataKey as string,
  }),
} as const;

/**
 * Routes for viewing and managing metadata/secrets:
 * - /private/:metadataKey - View metadata and secret details
 * - /private/:metadataKey/burn - Permanently delete a secret
 */
const routes: Array<RouteRecordRaw> = [
  {
    path: '/private/:metadataKey',
    name: 'Metadata link',
    component: ShowMetadata,
    ...withValidatedMetadataKey,
    meta: {
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayLinks: true,
        displayFeedback: true,
        displayVersion: true,
        displayPoweredBy: true,
      },
    },
  },
  {
    path: '/private/:metadataKey/burn',
    name: 'Burn secret',
    component: BurnSecret,
    ...withValidatedMetadataKey,
    meta: {
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayPoweredBy: true,
      },
    },
  },
];

export default routes;
