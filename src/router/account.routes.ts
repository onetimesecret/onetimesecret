// src/router/account.routes.ts

import ExpandedHeader from '@/components/layout/ExpandedHeader.vue';
import ExpandedFooter from '@/components/layout/ExpandedFooter.vue';
import AccountLayout from '@/layouts/AccountLayout.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/account',
    name: 'Account',
    components: {
      default: () => import('@/views/account/settings/ProfileSettings.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.account',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/region',
    name: 'Data Region',
    components: {
      default: () => import('@/views/account/DataRegion.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.data_region',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/region/current',
    name: 'Current Region',
    components: {
      default: () => import('@/views/account/region/CurrentRegion.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.current_region',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/region/available',
    name: 'Available Regions',
    components: {
      default: () => import('@/views/account/region/AvailableRegions.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.available_regions',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/region/why',
    name: 'Why Data Sovereignty Matters',
    components: {
      default: () => import('@/views/account/region/WhyItMatters.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.why_data_sovereignty',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings',
    redirect: '/account/settings/profile',
  },
  {
    path: '/account/settings/profile',
    name: 'Profile Settings',
    components: {
      default: () => import('@/views/account/settings/ProfileSettings.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.profile_settings',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/security',
    name: 'Security Overview',
    components: {
      default: () => import('@/views/account/settings/SecurityOverview.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.security_overview',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/security/password',
    name: 'Change Password',
    components: {
      default: () => import('@/views/account/ChangePassword.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.change_password',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/security/mfa',
    name: 'Multi-Factor Authentication',
    components: {
      default: () => import('@/views/account/MfaSettings.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.mfa_settings',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/security/sessions',
    name: 'Active Sessions',
    components: {
      default: () => import('@/views/account/ActiveSessions.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.active_sessions',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/security/recovery-codes',
    name: 'Recovery Codes',
    components: {
      default: () => import('@/views/account/RecoveryCodes.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.recovery_codes',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/api',
    name: 'API Settings',
    components: {
      default: () => import('@/views/account/settings/ApiSettings.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.api_settings',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/caution',
    name: 'Advanced Settings',
    components: {
      default: () => import('@/views/account/settings/CautionZone.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
      title: 'web.TITLES.advanced_settings',
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/organizations',
    name: 'Organizations Settings',
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
    path: '/account/settings/organization/:orgid',
    name: 'Organization Settings',
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
    path: '/account/billing',
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
    path: '/account/billing/plans',
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
    path: '/account/billing/invoices',
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
  // Legacy route for backward compatibility
  {
    path: '/account/settings/close',
    redirect: '/account/settings/caution',
  },
];

export default routes;
