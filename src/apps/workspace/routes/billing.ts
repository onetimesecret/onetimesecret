// src/apps/workspace/routes/billing.ts

import WorkspaceLayout from '@/apps/workspace/layouts/WorkspaceLayout.vue';
import { WindowService } from '@/services/window.service';
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
      scopesAvailable: SCOPE_PRESETS.orgLockedDomainHide,
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
      scopesAvailable: SCOPE_PRESETS.orgLockedDomainHide,
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
      scopesAvailable: SCOPE_PRESETS.orgLockedDomainHide,
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
  // Legacy billing redirects to /org moved to organizations.ts
  // These billing-prefixed org redirects remain for backwards compatibility
  {
    path: '/billing/organizations',
    redirect: '/org',
  },
  {
    path: '/billing/organization/:extid',
    redirect: (to) => ({
      path: `/org/${to.params.extid}`,
    }),
  },
  {
    path: '/billing/orgs',
    redirect: '/org',
  },
  {
    path: '/billing/org/:extid',
    redirect: (to) => ({
      path: `/org/${to.params.extid}`,
    }),
  },
];

export default routes;
