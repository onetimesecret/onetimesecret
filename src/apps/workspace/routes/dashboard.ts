// src/apps/workspace/routes/dashboard.ts

import WorkspaceLayout from '@/apps/workspace/layouts/WorkspaceLayout.vue';
import DashboardMain from '@/apps/workspace/dashboard/DashboardMain.vue';
import DashboardRecent from '@/apps/workspace/dashboard/DashboardRecent.vue';
import type { RouteRecordRaw } from 'vue-router';
import { SCOPE_PRESETS } from '@/types/router';

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
      scopesAvailable: SCOPE_PRESETS.showBoth,
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
      scopesAvailable: SCOPE_PRESETS.showBoth,
    },
  },
  // Org-qualified domain routes
  {
    path: '/org/:orgid/domains/add',
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
      scopesAvailable: SCOPE_PRESETS.showBoth,
    },
    props: true,
  },
  {
    path: '/org/:orgid/domains/:extid/verify',
    name: 'DomainVerify',
    component: () => import('@/apps/workspace/domains/DomainVerify.vue'),
    meta: {
      title: 'web.TITLES.domain_verify',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
      scopesAvailable: {
        organization: 'show',
        domain: 'show',
        onOrgSwitch: '/dashboard',
        onDomainSwitch: 'same',
      },
    },
    props: true,
  },
  {
    path: '/org/:orgid/domains/:extid/brand',
    name: 'DomainBrand',
    component: () => import('@/apps/workspace/domains/DomainBrand.vue'),
    meta: {
      title: 'web.TITLES.domain_brand',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
      scopesAvailable: {
        organization: 'show',
        domain: 'show',
        onOrgSwitch: '/dashboard',
        onDomainSwitch: 'same',
      },
    },
    props: true,
  },
  // Legacy redirects for backward compatibility
  {
    path: '/domains',
    redirect: '/dashboard',
  },
  {
    path: '/domains/add',
    redirect: '/dashboard',
  },
  {
    path: '/domains/:extid/verify',
    redirect: '/dashboard',
  },
  {
    path: '/domains/:extid/brand',
    redirect: '/dashboard',
  },
];

export default routes;
