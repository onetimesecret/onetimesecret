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
      title: 'web.TITLES.dashboard',
      requiresAuth: true,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
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
      title: 'web.TITLES.recent',
      requiresAuth: true,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
        displayVersion: true,
      },
    },
  },
  {
    path: '/domains',
    name: 'DashboardDomains',
    components: {
      default: () => import('@/views/dashboard/DashboardDomains.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      title: 'web.TITLES.domains',
      requiresAuth: true,
      layoutProps: {
        displayFeedback: true,
        displayPoweredBy: false,
      },
    },
    props: true,
  },
  {
    path: '/domains/add',
    name: 'DomainAdd',
    components: {
      default: () => import('@/views/dashboard/DashboardDomainAdd.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      title: 'web.TITLES.domain_add',
      requiresAuth: true,
      layoutProps: {
        displayFeedback: false,
        displayPoweredBy: false,
      },
    },
    props: true,
  },
  {
    path: '/domains/:domain/verify',
    name: 'DomainVerify',
    components: {
      default: () => import('@/views/dashboard/DashboardDomainVerify.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      title: 'web.TITLES.domain_verify',
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
    props: true,
  },
  {
    path: '/domains/:domain/brand',
    name: 'DomainBrand',
    components: {
      default: () => import('@/views/dashboard/DashboardDomainBrand.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      title: 'web.TITLES.domain_brand',
      requiresAuth: true,
      displayPoweredBy: false,
    },
    props: true,
  },
];

export default routes;
