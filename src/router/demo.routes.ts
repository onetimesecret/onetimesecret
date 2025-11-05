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
];

export default routes;
