// src/apps/secret/routes/incoming.ts

import SecretLayout from '@/apps/secret/layouts/SecretLayout.vue';
import type { RouteRecordRaw } from 'vue-router';
import { SCOPE_PRESETS } from '@/types/router';

const incomingRoutes: RouteRecordRaw[] = [
  {
    path: '/incoming',
    name: 'IncomingSecretForm',
    component: () => import('@/apps/secret/conceal/IncomingForm.vue'),
    meta: {
      requiresAuth: false,
      title: 'Send a Secret',
      layout: SecretLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayPoweredBy: false,
        displayVersion: false,
        displayToggles: true,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/incoming/:metadataKey',
    name: 'IncomingSuccess',
    component: () => import('@/apps/secret/conceal/IncomingSuccess.vue'),
    meta: {
      requiresAuth: false,
      title: 'Secret Sent Successfully',
      layout: SecretLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayPoweredBy: false,
        displayVersion: false,
        displayToggles: true,
      },
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
];

export default incomingRoutes;
