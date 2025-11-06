// src/router/dashboard.routes.ts

import ImprovedFooter from '@/components/layout/ImprovedFooter.vue';
import ImprovedHeader from '@/components/layout/ImprovedHeader.vue';
import ImprovedLayout from '@/layouts/ImprovedLayout.vue';
import DashboardIndex from '@/views/dashboard/DashboardIndex.vue';
import DashboardRecent from '@/views/dashboard/DashboardRecent.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/dashboard',
    name: 'Dashboard',
    components: {
      default: DashboardIndex,
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
      default: () => import('@/views/dashboard/DashboardDomains.vue'),
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
      default: () => import('@/views/dashboard/DashboardDomainAdd.vue'),
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
    path: '/domains/:domain/verify',
    name: 'DomainVerify',
    components: {
      default: () => import('@/views/dashboard/DashboardDomainVerify.vue'),
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
    path: '/domains/:domain/brand',
    name: 'DomainBrand',
    components: {
      default: () => import('@/views/dashboard/DashboardDomainBrand.vue'),
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
