// src/router/account.routes.ts

import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/account',
    name: 'Account',
    components: {
      default: () => import('@/views/account/AccountIndex.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
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
    name: 'Account Settings',
    components: {
      default: () => import('@/views/account/AccountSettingsIndex.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/password',
    name: 'Change Password',
    components: {
      default: () => import('@/views/account/ChangePassword.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/sessions',
    name: 'Active Sessions',
    components: {
      default: () => import('@/views/account/ActiveSessions.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/mfa',
    name: 'Multi-Factor Authentication',
    components: {
      default: () => import('@/views/account/MfaSettings.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/recovery-codes',
    name: 'Recovery Codes',
    components: {
      default: () => import('@/views/account/RecoveryCodes.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
  {
    path: '/account/settings/close',
    name: 'Close Account',
    components: {
      default: () => import('@/views/account/CloseAccount.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
    },
  },
];

export default routes;
