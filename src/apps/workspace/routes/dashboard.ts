// src/apps/workspace/routes/dashboard.ts

import WorkspaceLayout from '@/apps/workspace/layouts/WorkspaceLayout.vue';
import DashboardMain from '@/apps/workspace/dashboard/DashboardMain.vue';
import DashboardRecent from '@/apps/workspace/dashboard/DashboardRecent.vue';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { RouteLocationNormalized, RouteRecordRaw } from 'vue-router';
import { SCOPE_PRESETS } from '@/types/router';

/** Resolve the active org's extid at navigation time, falling back to dashboard */
function activeOrgPath(suffix: string) {
  return () => {
    const orgExtid = useOrganizationStore().currentOrganization?.extid;
    return orgExtid ? `/org/${orgExtid}/${suffix}` : '/dashboard';
  };
}

/**
 * Route guard: only org owners/admins may reach the "add custom domain" page (#3033).
 *
 * Resolves the target org by the route's :orgid (extid). When the role is
 * knowable and is 'member', redirect to the org's domains list. Unknown role
 * (org list not yet fetched, fresh page load) lets navigation proceed — the
 * page itself has a defensive v-if and the backend rejects with 403.
 */
function requireDomainAdminRole(to: RouteLocationNormalized) {
  const orgExtid = to.params.orgid as string | undefined;
  if (!orgExtid) return true;

  const store = useOrganizationStore();
  const org =
    store.getOrganizationByExtid(orgExtid) ??
    (store.currentOrganization?.extid === orgExtid ? store.currentOrganization : null);

  const role = org?.current_user_role ?? null;
  if (role === 'owner' || role === 'admin' || role === null) return true;

  return { path: `/org/${orgExtid}/domains` };
}

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
      sentryScrubParams: false,
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
      sentryScrubParams: false,
    },
  },
  // Org-qualified domain routes
  {
    path: '/org/:orgid/domains/add',
    name: 'DomainAdd',
    component: () => import('@/apps/workspace/domains/DomainAdd.vue'),
    beforeEnter: requireDomainAdminRole,
    meta: {
      title: 'web.TITLES.domain_add',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: {
        displayFeedback: false,
        displayPoweredBy: false,
      },
      scopesAvailable: SCOPE_PRESETS.showBoth,
      sentryScrubParams: false,
    },
    props: true,
  },
  {
    path: '/org/:orgid/domains/:extid',
    name: 'DomainDetail',
    component: () => import('@/apps/workspace/domains/DomainDetail.vue'),
    meta: {
      title: 'web.TITLES.domain_detail',
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
      sentryScrubParams: false,
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
      sentryScrubParams: false,
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
      sentryScrubParams: false,
    },
    props: true,
  },
  {
    path: '/org/:orgid/domains/:extid/sso',
    name: 'DomainSso',
    component: () => import('@/apps/workspace/domains/DomainSso.vue'),
    meta: {
      title: 'web.TITLES.domain_sso',
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
      sentryScrubParams: false,
    },
    props: true,
  },
  {
    path: '/org/:orgid/domains/:extid/email',
    name: 'DomainEmail',
    component: () => import('@/apps/workspace/domains/DomainEmail.vue'),
    meta: {
      title: 'web.TITLES.domain_email',
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
      sentryScrubParams: false,
    },
    props: true,
  },
  {
    path: '/org/:orgid/domains/:extid/incoming',
    name: 'DomainIncoming',
    component: () => import('@/apps/workspace/domains/DomainIncoming.vue'),
    meta: {
      title: 'web.TITLES.domain_incoming',
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
      sentryScrubParams: false,
    },
    props: true,
  },
  // Legacy redirects — resolve to org-scoped equivalents using the active organization
  {
    path: '/domains',
    redirect: activeOrgPath('domains'),
  },
  {
    path: '/domains/add',
    redirect: activeOrgPath('domains/add'),
  },
  {
    path: '/domains/:extid/verify',
    redirect: (to) => {
      const orgExtid = useOrganizationStore().currentOrganization?.extid;
      return orgExtid ? `/org/${orgExtid}/domains/${to.params.extid}/verify` : '/dashboard';
    },
  },
  {
    path: '/domains/:extid/brand',
    redirect: (to) => {
      const orgExtid = useOrganizationStore().currentOrganization?.extid;
      return orgExtid ? `/org/${orgExtid}/domains/${to.params.extid}/brand` : '/dashboard';
    },
  },
];

export default routes;
