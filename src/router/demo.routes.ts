// src/router/demo.routes.ts

import ImprovedHeader from '@/components/layout/ImprovedHeader.vue';
import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import ImprovedLayout from '@/layouts/ImprovedLayout.vue';
import NavigationDemo from '@/views/demo/NavigationDemo.vue';
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
];

export default routes;
