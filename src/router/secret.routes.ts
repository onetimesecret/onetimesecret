import QuietHeader from '@/components/layout/QuietHeader.vue';
import ShowSecretContainer from '@/views/secrets/ShowSecretContainer.vue';
import { RouteLocationNormalized, RouteRecordRaw } from 'vue-router';

/**
 * Type guard that validates a metadata key.
 * @param key - The key to validate
 * @returns true if key is a string matching /^[a-zA-Z0-9]+$/
 */
const validateSecretKey = (key: string | string[]): key is string =>
  typeof key === 'string' && /^[a-zA-Z0-9]+$/.test(key);

/**
 * Shared route configuration for metadata-related routes.
 * Handles validation and type safety for the secretKey parameter.
 *
 * - Validates secretKey format in beforeEnter guard
 * - Redirects to Not Found for invalid keys
 * - Provides typed secretKey prop to components
 */
const secretKeyProps = (route: RouteLocationNormalized) => ({
  secretKey: route.params.secretKey as string,
});

const withValidatedSecretKey = {
  beforeEnter: (to: RouteLocationNormalized) => {
    const isValid = validateSecretKey(to.params.secretKey);

    if (!isValid) {
      return { name: 'Not Found' };
    }
  },
  props: { default: secretKeyProps },
} as const;

/**
 * Routes
 */
const routes: RouteRecordRaw[] = [
  {
    path: '/secret/:secretKey',
    name: 'Secret link',
    components: { default: ShowSecretContainer, header: QuietHeader },
    meta: {
      requiresAuth: false,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayPoweredBy: false,
        displayVersion: false,
      },
    },
    ...withValidatedSecretKey,
  },
];
export default routes;
