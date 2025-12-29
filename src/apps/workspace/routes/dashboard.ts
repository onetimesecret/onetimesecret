// src/apps/workspace/routes/dashboard.ts

import WorkspaceLayout from '@/apps/workspace/layouts/WorkspaceLayout.vue';
import DashboardMain from '@/apps/workspace/dashboard/DashboardMain.vue';
import DashboardRecent from '@/apps/workspace/dashboard/DashboardRecent.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/dashboard',
    name: 'Dashboard',
    component: DashboardMain,
    meta: {
      title: 'web.TITLES.dashboard',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: false,
        displayPoweredBy: false,
        displayVersion: true,
        showSidebar: false,
      },
    },
  },
  {
    path: '/recent',
    name: 'Recents',
    component: DashboardRecent,
    meta: {
      title: 'web.TITLES.recent',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: {
        displayMasthead: true,
        displayNavigation: true,
        displayFooterLinks: true,
        displayFeedback: false,
        displayPoweredBy: false,
        displayVersion: true,
      },
    },
  },
  {
    path: '/domains',
    name: 'DashboardDomains',
    component: () => import('@/apps/workspace/domains/DomainsList.vue'),
    meta: {
      title: 'web.TITLES.domains',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: {
        displayFeedback: false,
        displayPoweredBy: false,
      },
    },
    props: true,
  },
  {
    path: '/domains/add',
    name: 'DomainAdd',
    component: () => import('@/apps/workspace/domains/DomainAdd.vue'),
    meta: {
      title: 'web.TITLES.domain_add',
      requiresAuth: true,
      layout: WorkspaceLayout,
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
    component: () => import('@/apps/workspace/domains/DomainVerify.vue'),
    meta: {
      title: 'web.TITLES.domain_verify',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
    props: true,
  },
  {
    path: '/domains/:extid/brand',
    name: 'DomainBrand',
    component: () => import('@/apps/workspace/domains/DomainBrand.vue'),
    meta: {
      title: 'web.TITLES.domain_brand',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
    props: true,
  },
];

export default routes;
