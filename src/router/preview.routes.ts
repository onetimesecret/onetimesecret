// src/router/preview.routes.ts

import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import DefaultLayout from '@/layouts/DefaultLayout.vue';
import { RouteRecordRaw } from 'vue-router';

const sharedMeta = {
  requiresAuth: false,
  layout: DefaultLayout,
  layoutProps: {
    displayMasthead: true,
    displayNavigation: true,
    displayFooterLinks: true,
    displayFeedback: true,
    displayPoweredBy: false,
    displayVersion: true,
    displayToggles: true,
  },
};

const routes: Array<RouteRecordRaw> = [
  {
    path: '/preview/copy-first',
    name: 'Preview Copy-First',
    components: {
      default: () => import('@/views/PreviewCreate.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: sharedMeta,
  },
];

export default routes;
