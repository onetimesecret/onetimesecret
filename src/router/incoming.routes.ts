// src/router/incoming.routes.ts

import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import QuietHeader from '@/components/layout/QuietHeader.vue';
import DefaultLayout from '@/layouts/DefaultLayout.vue';
import type { RouteRecordRaw } from 'vue-router';

const incomingRoutes: RouteRecordRaw[] = [
  {
    path: '/incoming',
    name: 'IncomingSecretForm',
    components: {
      default: () => import('@/views/incoming/IncomingSecretForm.vue'),
      header: QuietHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: false,
      title: 'Send a Secret',
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayPoweredBy: false,
        displayVersion: true,
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
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: false,
      title: 'Secret Sent Successfully',
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: false,
        displayPoweredBy: false,
        displayVersion: true,
        displayToggles: true,
      },
    },
  },
];

export default incomingRoutes;
