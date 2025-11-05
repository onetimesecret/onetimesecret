// src/router/demo.routes.ts

import ImprovedHeader from '@/components/layout/ImprovedHeader.vue';
import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import EmptyHeader from '@/components/layout/EmptyHeader.vue';
import ImprovedLayout from '@/layouts/ImprovedLayout.vue';
import NavigationDemo from '@/views/demo/NavigationDemo.vue';
import NavigationCodaDemo from '@/views/demo/NavigationCodaDemo.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/demo/navigation',
    name: 'NavigationDemo',
    components: {
      default: NavigationDemo,
      header: ImprovedHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
        displayVersion: true,
        // Sidebar options are handled in the ImprovedLayout component
      },
    },
  },
  {
    path: '/demo/team-navigation',
    name: 'TeamNavigationDemo',
    components: {
      default: () => import('@/views/demo/TeamNavigationDemo.vue'),
      // Note: TeamNavigationDemo includes its own header, so header component is handled by EmptyHeader
      header: () => import('@/components/layout/EmptyHeader.vue'),
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: true,
        displayFeedback: false,
        displayPoweredBy: false,
        displayVersion: true,
      },
    },
  },
  {
    path: '/demo/navigation-coda',
    name: 'NavigationCodaDemo',
    components: {
      default: NavigationCodaDemo,
      // Coda demo handles its own layout completely (full-screen split view)
      header: EmptyHeader,
      footer: () => import('@/components/layout/EmptyFooter.vue'),
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayPoweredBy: false,
        displayVersion: false,
      },
    },
  },
];

export default routes;
