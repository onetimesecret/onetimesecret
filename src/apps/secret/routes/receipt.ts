// src/apps/secret/routes/receipt.ts

import SecretLayout from '@/apps/secret/layouts/SecretLayout.vue';
import BurnSecret from '@/apps/secret/reveal/BurnSecret.vue';
import ShowReceipt from '@/apps/secret/reveal/ShowReceipt.vue';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { SCOPE_PRESETS } from '@/types/router';
import type { RouteLocationNormalized, RouteRecordRaw } from 'vue-router';

/**
 * Type guard that validates a receipt key.
 * @param key - The key to validate
 * @returns true if key is a string matching /^[a-zA-Z0-9]+$/
 */
const validateReceiptKey = (key: string | string[]): key is string =>
  typeof key === 'string' && /^[a-zA-Z0-9]+$/.test(key);

/**
 * Shared route configuration for receipt-related routes.
 * Handles validation and type safety for the receiptIdentifier parameter.
 *
 * - Validates receiptIdentifier format in beforeEnter guard
 * - Redirects to Not Found for invalid keys
 * - Provides typed receiptIdentifier prop to components
 */
const withValidatedReceiptKey = {
  beforeEnter: (to: RouteLocationNormalized) => {
    // Use bootstrap store for domain strategy
    const bootstrapStore = useBootstrapStore();
    const domainStrategy = bootstrapStore.domain_strategy as string;

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

    const isValid = validateReceiptKey(to.params.receiptIdentifier);
    if (!isValid) {
      return { name: 'NotFound' };
    }
  },
  props: (route: RouteLocationNormalized) => ({
    receiptIdentifier: route.params.receiptIdentifier as string,
  }),
} as const;

/**
 * Routes for viewing and managing receipts:
 * - /receipt/:receiptIdentifier - View receipt and secret details
 * - /receipt/:receiptIdentifier/burn - Permanently delete a secret
 */
const routes: Array<RouteRecordRaw> = [
  {
    path: '/receipt/:receiptIdentifier',
    name: 'Receipt link',
    component: ShowReceipt,
    ...withValidatedReceiptKey,
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
      scopesAvailable: SCOPE_PRESETS.lockBoth,
    },
  },
  {
    path: '/receipt/:receiptIdentifier/burn',
    name: 'Burn receipt',
    component: BurnSecret,
    ...withValidatedReceiptKey,
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
    path: '/receipt/:receiptIdentifier/burn',
    name: 'Burn secret',
    component: BurnSecret,
    ...withValidatedReceiptKey,
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
