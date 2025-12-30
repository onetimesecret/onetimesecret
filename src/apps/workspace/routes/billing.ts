// src/apps/workspace/routes/billing.ts

import WorkspaceLayout from '@/apps/workspace/layouts/WorkspaceLayout.vue';
import { WindowService } from '@/services/window.service';
import { RouteRecordRaw } from 'vue-router';

const standardLayoutProps = {
  displayMasthead: true,
  displayNavigation: true,
  displayFooterLinks: true,
  displayFeedback: false,
  displayPoweredBy: false,
  displayVersion: true,
  showSidebar: false,
} as const;

/**
 * Guard to check if billing is enabled before accessing billing routes
 * Redirects to dashboard with notification if billing is disabled
 */
function checkBillingEnabled() {
  const billingEnabled = WindowService.get('billing_enabled');

  if (!billingEnabled) {
    return { name: 'Dashboard' };
  }

  return true;
}

const routes: Array<RouteRecordRaw> = [
  {
    path: '/billing',
    redirect: '/billing/overview',
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/billing/overview',
    name: 'Billing Overview',
    beforeEnter: checkBillingEnabled,
    component: () => import('@/apps/workspace/billing/BillingOverview.vue'),
    meta: {
      title: 'web.billing.overview.title',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/org',
    name: 'Organizations',
    beforeEnter: checkBillingEnabled,
    component: () => import('@/apps/workspace/account/settings/OrganizationsSettings.vue'),
    meta: {
      title: 'web.TITLES.organizations_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
    },
  },
  // Redirect /org/domains to /domains to prevent it being caught by :extid
  {
    path: '/org/domains',
    redirect: '/domains',
  },
  {
    path: '/org/:extid',
    name: 'Organization Settings',
    beforeEnter: checkBillingEnabled,
    component: () => import('@/apps/workspace/account/settings/OrganizationSettings.vue'),
    meta: {
      title: 'web.TITLES.organization_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/billing/plans',
    name: 'Billing Plans',
    beforeEnter: checkBillingEnabled,
    component: () => import('@/apps/workspace/billing/PlanSelector.vue'),
    meta: {
      title: 'web.billing.plans.title',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/billing/invoices',
    name: 'Billing Invoices',
    beforeEnter: checkBillingEnabled,
    component: () => import('@/apps/workspace/billing/InvoiceList.vue'),
    meta: {
      title: 'web.billing.invoices.title',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
    },
  },
  // Legacy routes for backward compatibility
  {
    path: '/account/billing',
    redirect: '/billing/overview',
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/account/billing/plans',
    redirect: '/billing/plans',
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/account/billing/invoices',
    redirect: '/billing/invoices',
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/account/settings/organizations',
    redirect: '/org',
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/account/settings/organization/:extid',
    redirect: (to) => ({
      path: `/org/${to.params.extid}`,
    }),
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/billing/organizations',
    redirect: '/org',
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/billing/organization/:extid',
    redirect: (to) => ({
      path: `/org/${to.params.extid}`,
    }),
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/billing/orgs',
    redirect: '/org',
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/billing/org/:extid',
    redirect: (to) => ({
      path: `/org/${to.params.extid}`,
    }),
    beforeEnter: checkBillingEnabled,
  },
];

export default routes;
