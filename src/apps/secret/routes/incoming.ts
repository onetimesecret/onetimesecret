// src/apps/secret/routes/incoming.ts

import ImprovedFooter from '@/shared/components/layout/ImprovedFooter.vue';
import ImprovedHeader from '@/shared/components/layout/ImprovedHeader.vue';
import type { RouteRecordRaw } from 'vue-router';

const incomingRoutes: RouteRecordRaw[] = [
  {
    path: '/incoming',
    name: 'IncomingSecretForm',
    components: {
      default: () => import('@/apps/secret/conceal/IncomingForm.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      requiresAuth: false,
      title: 'Send a Secret',
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayPoweredBy: false,
        displayVersion: false,
        displayToggles: true,
      },
    },
  },
  {
    path: '/incoming/:metadataKey',
    name: 'IncomingSuccess',
    components: {
      default: () => import('@/apps/secret/conceal/IncomingSuccess.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      requiresAuth: false,
      title: 'Secret Sent Successfully',
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayPoweredBy: false,
        displayVersion: false,
        displayToggles: true,
      },
    },
  },
];

export default incomingRoutes;
