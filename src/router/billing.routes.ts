// src/router/billing.routes.ts

import {
  ImprovedFooter,
  ImprovedHeader,
  ImprovedLayout,
  standardLayoutProps,
} from './layout.config';
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
      default: () => import('@/views/billing/BillingOverview.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.billing.overview.title',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/billing/orgs',
    name: 'Billing Organizations',
    beforeEnter: checkBillingEnabled,
    components: {
      default: () => import('@/views/account/settings/OrganizationsSettings.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.organizations_settings',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/billing/org/:extid',
    name: 'Billing Organization Settings',
    beforeEnter: checkBillingEnabled,
    components: {
      default: () => import('@/views/account/settings/OrganizationSettings.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
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
      default: () => import('@/views/billing/PlanSelector.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
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
      default: () => import('@/views/billing/InvoiceList.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
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
    redirect: '/billing/orgs',
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/account/settings/organization/:extid',
    redirect: (to) => ({
      path: `/billing/org/${to.params.extid}`,
    }),
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/billing/organizations',
    redirect: '/billing/orgs',
    beforeEnter: checkBillingEnabled,
  },
  {
    path: '/billing/organization/:extid',
    redirect: (to) => ({
      path: `/billing/org/${to.params.extid}`,
    }),
    beforeEnter: checkBillingEnabled,
  },
];

export default routes;
