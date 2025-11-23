// src/router/incoming.routes.ts

import QuietFooter from '@/components/layout/QuietFooter.vue';
import QuietHeader from '@/components/layout/QuietHeader.vue';
import type { RouteRecordRaw } from 'vue-router';

const incomingRoutes: RouteRecordRaw[] = [
  {
    path: '/incoming',
    name: 'IncomingSecretForm',
    components: {
      default: () => import('@/views/incoming/IncomingSecretForm.vue'),
      header: QuietHeader,
      footer: QuietFooter,
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
      default: () => import('@/views/incoming/IncomingSuccessView.vue'),
      header: QuietHeader,
      footer: QuietFooter,
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
