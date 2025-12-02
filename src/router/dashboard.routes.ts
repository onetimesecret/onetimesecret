// src/router/dashboard.routes.ts

import ImprovedFooter from '@/shared/components/layout/ImprovedFooter.vue';
import ImprovedHeader from '@/shared/components/layout/ImprovedHeader.vue';
import ImprovedLayout from '@/shared/layouts/ManagementLayout.vue';
import DashboardContainer from '@/apps/workspace/dashboard/DashboardContainer.vue';
import DashboardRecent from '@/apps/workspace/dashboard/DashboardRecent.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/dashboard',
    name: 'Dashboard',
    components: {
      default: DashboardContainer,
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.dashboard',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: true,
        displayPoweredBy: false,
        displayVersion: true,
        showSidebar: false,
      },
    },
  },
  {
    path: '/recent',
    name: 'Recents',
    components: {
      default: DashboardRecent,
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.recent',
      requiresAuth: true,
      layout: ImprovedLayout,
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
      default: () => import('@/apps/workspace/domains/DomainsList.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.domains',
      requiresAuth: true,
      layout: ImprovedLayout,
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
      default: () => import('@/apps/workspace/domains/DomainAdd.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.domain_add',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: {
        displayFeedback: false,
        displayPoweredBy: false,
      },
    },
    props: true,
  },
  {
    path: '/domains/:extid/verify',
    name: 'DomainVerify',
    components: {
      default: () => import('@/apps/workspace/domains/DomainVerify.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.domain_verify',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
    props: true,
  },
  {
    path: '/domains/:extid/brand',
    name: 'DomainBrand',
    components: {
      default: () => import('@/apps/workspace/domains/DomainBrand.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.domain_brand',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
    props: true,
  },
];

export default routes;
