import DefaultLayout from '@/layouts/DefaultLayout.vue';
import QuietFooter from '@/components/layout/QuietFooter.vue';
import QuietHeader from '@/components/layout/QuietHeader.vue';
import BurnSecret from '@/views/secrets/BurnSecret.vue';
import ShowMetadata from '@/views/secrets/ShowMetadata.vue';
import { RouteLocationNormalized, RouteRecordMultipleViews } from 'vue-router';
import { WindowService } from '@/services/window.service';

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
    // Use window service directly rather than the identity store
    // since the routes start before the pinia stores.
    const domainStrategy = WindowService.get('domain_strategy') as string;

    if (domainStrategy === 'custom') {
      to.meta.layoutProps = {
        ...to.meta.layoutProps,
        displayMasthead: true,
        displayNavigation: false,
        displayLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayPoweredBy: true,
        displayToggles: true,
      };
    }

    const isValid = validateMetadataKey(to.params.metadataKey);
    if (!isValid) {
      return { name: 'Not Found' };
    }
  },
  props: {
    default: (route: RouteLocationNormalized) => ({
      metadataKey: route.params.metadataKey as string,
    }),
    header: false,
    footer: false,
  },
} as const;

/**
 * Routes for viewing and managing metadata/secrets:
 * - /private/:metadataKey - View metadata and secret details
 * - /private/:metadataKey/burn - Permanently delete a secret
 */
const routes: Array<RouteRecordMultipleViews> = [
  {
    path: '/private/:metadataKey',
    name: 'Metadata link',
    components: {
      default: ShowMetadata,
      header: QuietHeader,
      footer: QuietFooter,
    },
    ...withValidatedMetadataKey,
    meta: {
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
        displayVersion: true,
        displayToggles: true,
      },
    },
  },
  {
    path: '/private/:metadataKey/burn',
    name: 'Burn secret',
    components: {
      default: BurnSecret,
      header: QuietHeader,
      footer: QuietFooter,
    },
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
