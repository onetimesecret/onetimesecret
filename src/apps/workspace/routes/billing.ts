// src/apps/workspace/routes/billing.ts

import WorkspaceLayout from '@/apps/workspace/layouts/WorkspaceLayout.vue';
import { WindowService } from '@/services/window.service';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { RouteRecordRaw } from 'vue-router';

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
 * Guard to check if billing is enabled before accessing billing routes.
 * Redirects to dashboard if billing is disabled.
 */
function checkBillingEnabled() {
  const billingEnabled = WindowService.get('billing_enabled');

  if (!billingEnabled) {
    return { name: 'Dashboard' };
  }

  return true;
}

/**
 * Guard to redirect /billing to /billing/:extid/overview using the current org.
 */
async function redirectToDefaultOrg() {
  const organizationStore = useOrganizationStore();

  if (organizationStore.organizations.length === 0) {
    await organizationStore.fetchOrganizations();
  }

  const org = organizationStore.currentOrganization || organizationStore.organizations[0];
  return { path: `/billing/${org.extid}/overview` };
}

const routes: Array<RouteRecordRaw> = [
  // Redirect /billing to default org's billing page
  {
    path: '/billing',
    beforeEnter: [checkBillingEnabled, redirectToDefaultOrg],
    component: () => import('@/apps/workspace/billing/BillingOverview.vue'),
  },
  {
    path: '/billing/:extid/overview',
    name: 'Billing Overview',
    beforeEnter: checkBillingEnabled,
    component: () => import('@/apps/workspace/billing/BillingOverview.vue'),
    meta: {
      title: 'web.billing.overview.title',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: {
        organization: 'show',
        domain: 'hide',
        onOrgSwitch: 'same',
      },
    },
  },
  {
    path: '/billing/:extid/plans',
    name: 'Billing Plans',
    beforeEnter: checkBillingEnabled,
    component: () => import('@/apps/workspace/billing/PlanSelector.vue'),
    meta: {
      title: 'web.billing.plans.title',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: {
        organization: 'show',
        domain: 'hide',
        onOrgSwitch: 'same',
      },
    },
  },
  {
    path: '/billing/:extid/invoices',
    name: 'Billing Invoices',
    beforeEnter: checkBillingEnabled,
    component: () => import('@/apps/workspace/billing/InvoiceList.vue'),
    meta: {
      title: 'web.billing.invoices.title',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: {
        organization: 'show',
        domain: 'hide',
        onOrgSwitch: 'same',
      },
    },
  },
];

export default routes;
