// src/router/public.routes.ts

import QuietFooter from '@/components/layout/QuietFooter.vue';
import QuietHeader from '@/components/layout/QuietHeader.vue';
import DefaultLayout from '@/layouts/DefaultLayout.vue';
import QuietLayout from '@/layouts/QuietLayout.vue';
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
      header: QuietHeader,
      footer: QuietFooter,
    },
    meta: {
      requiresAuth: false,
      layout: QuietLayout,
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
    beforeEnter: async (to) => {
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
    path: '/info/privacy',
    name: 'Privacy Policy',
    component: () => import('@/views/info/PrivacyDoc.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
    },
  },
  {
    path: '/info/terms',
    name: 'Terms of Use',
    component: () => import('@/views/info/TermsDoc.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
    },
  },
  {
    path: '/info/security',
    name: 'Security Policy',
    component: () => import('@/views/info/SecurityDoc.vue'),
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
        displayLinks: true,
        displayFeedback: false,
      },
    },
  },
  {
    path: '/about',
    name: 'About',
    component: () => import('@/views/About.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: true,
      },
    },
  },
  {
    path: '/translations',
    name: 'Translations',
    component: () => import('@/views/Translations.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: true,
      },
    },
  },
  {
    path: '/info/icons',
    name: 'Icons',
    component: () => import('@/views/info/IconsInfo.vue'),
    meta: {
      requiresAuth: false,
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayLinks: true,
        displayFeedback: true,
      },
    },
  },
];

export default routes;
