import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import DefaultLayout from '@/layouts/DefaultLayout.vue';
import AccountDomains from '@/views/account/AccountDomains.vue';
import DashboardIndex from '@/views/dashboard/DashboardIndex.vue';
import DashboardRecent from '@/views/dashboard/DashboardRecent.vue';
import BurnSecret from '@/views/secrets/BurnSecret.vue';
import ShowMetadata from '@/views/secrets/ShowMetadata.vue';
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
  {
    path: '/account/domains',
    name: 'AccountDomains',
    components: {
      default: AccountDomains,
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
    },
    props: true,
  },
  {
    path: '/private/:metadataKey',
    name: 'Metadata link',
    component: ShowMetadata,
    props: true,
    beforeEnter: (to) => {
      // Validate metadataKey format
      const key = to.params.metadataKey as string;
      if (!/^[a-zA-Z0-9]+$/.test(key)) {
        return { name: 'Not Found' };
      }
    },
    meta: {
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayLinks: true,
        displayFeedback: true,
        displayVersion: true,
        displayPoweredBy: true,
      },
    },
  },
  {
    path: '/private/:metadataKey/burn',
    name: 'Burn secret',
    component: BurnSecret,
    props: true,
    beforeEnter: (to) => {
      // Validate metadataKey format
      const key = to.params.metadataKey as string;
      if (!/^[a-zA-Z0-9]+$/.test(key)) {
        return { name: 'Not Found' };
      }
    },
    meta: {
      layout: DefaultLayout,
      layoutProps: {
        displayMasthead: false,
        displayNavigation: false,
        displayLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayPoweredBy: true,
      },
    },
  },
];

export default routes;
