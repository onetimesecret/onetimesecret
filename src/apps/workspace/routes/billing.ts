// src/apps/workspace/routes/billing.ts

import {
  ImprovedHeader,
  ImprovedLayout,
  standardLayoutProps,
  WorkspaceFooter,
} from '@/router/layout.config';
import { WindowService } from '@/services/window.service';
import { RouteRecordRaw } from 'vue-router';

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
    components: {
      default: () => import('@/apps/workspace/billing/BillingOverview.vue'),
      header: ImprovedHeader,
      footer: WorkspaceFooter,
    },
    meta: {
      title: 'web.billing.overview.title',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/org',
    name: 'Organizations',
    beforeEnter: checkBillingEnabled,
    components: {
      default: () => import('@/apps/workspace/account/settings/OrganizationsSettings.vue'),
      header: ImprovedHeader,
      footer: WorkspaceFooter,
    },
    meta: {
      title: 'web.TITLES.organizations_settings',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/org/:extid',
    name: 'Organization Settings',
    beforeEnter: checkBillingEnabled,
    components: {
      default: () => import('@/apps/workspace/account/settings/OrganizationSettings.vue'),
      header: ImprovedHeader,
      footer: WorkspaceFooter,
    },
    meta: {
      title: 'web.TITLES.organization_settings',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/billing/plans',
    name: 'Billing Plans',
    beforeEnter: checkBillingEnabled,
    components: {
      default: () => import('@/apps/workspace/billing/PlanSelector.vue'),
      header: ImprovedHeader,
      footer: WorkspaceFooter,
    },
    meta: {
      title: 'web.billing.plans.title',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/billing/invoices',
    name: 'Billing Invoices',
    beforeEnter: checkBillingEnabled,
    components: {
      default: () => import('@/apps/workspace/billing/InvoiceList.vue'),
      header: ImprovedHeader,
      footer: WorkspaceFooter,
    },
    meta: {
      title: 'web.billing.invoices.title',
      requiresAuth: true,
      layout: ImprovedLayout,
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
