// src/router/account.routes.ts

import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
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
      requiresAuth: true,
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
      requiresAuth: true,
      layout: AccountLayout,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/advanced',
    name: 'Advanced Settings',
    components: {
      default: () => import('@/views/account/settings/AdvancedSettings.vue'),
      header: ExpandedHeader,
      footer: ExpandedFooter,
    },
    meta: {
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
    redirect: '/account/settings/advanced',
  },
];

export default routes;
