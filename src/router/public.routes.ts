// src/router/public.routes.ts

import AlternateLogos from '@/components/logos/AlternateLogos.vue';
import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import DefaultLayout from '@/layouts/DefaultLayout.vue';
import { WindowService } from '@/services/window.service';
import HomepageContainer from '@/views/HomepageContainer.vue';
import IncomingSupportSecret from '@/views/secrets/IncomingSupportSecret.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/',
    name: 'Home',
    components: {
      default: HomepageContainer,
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: true,
        displayVersion: true,
        displayToggles: true,
      },
    },
    beforeEnter: async (to) => {
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
    },
  },
  {
    path: '/incoming',
    name: 'Inbound Secrets',
    component: IncomingSupportSecret,
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
    },
  },
  {
    path: '/icons',
    name: 'Icons',
    component: AlternateLogos,
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
    },
  },
  {
    path: '/feedback',
    name: 'Feedback',
    component: () => import('@/views/Feedback.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayFooterLinks: true,
        displayFeedback: false,
      },
    },
  },
];

export default routes;
