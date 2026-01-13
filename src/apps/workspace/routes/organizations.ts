// src/apps/workspace/routes/organizations.ts

/**
 * Routes for organization management
 *
 * Organizations are a workspace feature, not a billing feature.
 * These routes do not require billing to be enabled.
 */

import WorkspaceLayout from '@/apps/workspace/layouts/WorkspaceLayout.vue';
import type { RouteRecordRaw } from 'vue-router';
import { SCOPE_PRESETS } from '@/types/router';

const standardLayoutProps = {
  displayMasthead: true,
  displayNavigation: true,
  displayFooterLinks: true,
  displayFeedback: false,
  displayPoweredBy: false,
  displayVersion: true,
  showSidebar: false,
} as const;

const routes: Array<RouteRecordRaw> = [
  {
    path: '/org',
    name: 'Organizations',
    component: () => import('@/apps/workspace/account/settings/OrganizationsSettings.vue'),
    meta: {
      title: 'web.TITLES.organizations_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth, // Hide switcher on org list page
    },
  },
  // Route /org/domains to the OrganizationSettings page with domains tab active
  // This prevents it from being caught by :extid param
  {
    path: '/org/domains',
    redirect: '/domains',
  },
  {
    path: '/org/:extid',
    name: 'Organization Settings',
    component: () => import('@/apps/workspace/account/settings/OrganizationSettings.vue'),
    meta: {
      title: 'web.TITLES.organization_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth, // Hide switcher - org name shown in page header
    },
  },
  {
    path: '/org/:extid/members',
    name: 'OrganizationMembers',
    component: () => import('@/apps/workspace/members/MembersList.vue'),
    meta: {
      title: 'web.organizations.members.title',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.orgLockedDomainHide,
    },
    props: true,
  },
  {
    path: '/org/:extid/domains',
    name: 'OrganizationDomains',
    component: () => import('@/apps/workspace/account/settings/OrganizationSettings.vue'),
    meta: {
      title: 'web.domains.domains',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth, // Hide switcher - org name shown in page header
    },
    props: (route) => ({ extid: route.params.extid, initialTab: 'domains' }),
  },
  // Legacy redirects (no billing guard needed)
  {
    path: '/account/settings/organizations',
    redirect: '/org',
  },
  {
    path: '/account/settings/organization/:extid',
    redirect: (to) => ({
      path: `/org/${to.params.extid}`,
    }),
  },
];

export default routes;
