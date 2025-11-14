// src/router/billing.routes.ts

import ExpandedFooter from '@/components/layout/ExpandedFooter.vue';
import ExpandedHeader from '@/components/layout/ExpandedHeader.vue';
import AccountLayout from '@/layouts/AccountLayout.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/billing',
    redirect: '/billing/overview',
  },
  {
    path: '/billing/overview',
    name: 'Billing Overview',
    components: {
      default: () => import('@/views/billing/BillingOverview.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.billing.overview.title',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/billing/orgs',
    name: 'Billing Organizations',
    components: {
      default: () => import('@/views/account/settings/OrganizationsSettings.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.organizations_settings',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/billing/org/:extid',
    name: 'Billing Organization Settings',
    components: {
      default: () => import('@/views/account/settings/OrganizationSettings.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.organization_settings',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/billing/plans',
    name: 'Billing Plans',
    components: {
      default: () => import('@/views/billing/PlanSelector.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.billing.plans.title',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/billing/invoices',
    name: 'Billing Invoices',
    components: {
      default: () => import('@/views/billing/InvoiceList.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.billing.invoices.title',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  // Legacy routes for backward compatibility
  {
    path: '/account/billing',
    redirect: '/billing/overview',
  },
  {
    path: '/account/billing/plans',
    redirect: '/billing/plans',
  },
  {
    path: '/account/billing/invoices',
    redirect: '/billing/invoices',
  },
  {
    path: '/account/settings/organizations',
    redirect: '/billing/orgs',
  },
  {
    path: '/account/settings/organization/:extid',
    redirect: (to) => ({
      path: `/billing/org/${to.params.extid}`,
    }),
  },
  {
    path: '/billing/organizations',
    redirect: '/billing/orgs',
  },
  {
    path: '/billing/organization/:extid',
    redirect: (to) => ({
      path: `/billing/org/${to.params.extid}`,
    }),
  },
];

export default routes;
