import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import DashboardIndex from '@/views/dashboard/DashboardIndex.vue';
import DashboardRecent from '@/views/dashboard/DashboardRecent.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/dashboard',
    name: 'Dashboard',
    components: {
      default: DashboardIndex,
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayLinks: true,
        displayFeedback: true,
        displayVersion: true,
      },
    },
  },
  {
    path: '/recent',
    name: 'Recents',
    components: {
      default: DashboardRecent,
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayLinks: true,
        displayFeedback: true,
        displayVersion: true,
      },
    },
  },
];

export default routes;
