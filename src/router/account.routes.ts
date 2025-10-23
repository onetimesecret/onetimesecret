// src/router/account.routes.ts

import DefaultFooter from '@/components/layout/DefaultFooter.vue';
import DefaultHeader from '@/components/layout/DefaultHeader.vue';
import SettingsLayout from '@/components/layouts/SettingsLayout.vue';
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
    path: '/account/region',
    name: 'Data Region',
    components: {
      default: () => import('@/views/account/DataRegion.vue'),
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
    redirect: '/account/settings/profile',
  },
  {
    path: '/account/settings/profile',
    name: 'Profile Settings',
    components: {
      default: () => import('@/views/account/settings/ProfileSettings.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
      useSettingsLayout: true,
    },
  },
  {
    path: '/account/settings/security',
    name: 'Security Overview',
    components: {
      default: () => import('@/views/account/settings/SecurityOverview.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
      useSettingsLayout: true,
    },
  },
  {
    path: '/account/settings/security/password',
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
      useSettingsLayout: true,
    },
  },
  {
    path: '/account/settings/security/mfa',
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
      useSettingsLayout: true,
    },
  },
  {
    path: '/account/settings/security/sessions',
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
      useSettingsLayout: true,
    },
  },
  {
    path: '/account/settings/security/recovery-codes',
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
      useSettingsLayout: true,
    },
  },
  {
    path: '/account/settings/api',
    name: 'API Settings',
    components: {
      default: () => import('@/views/account/settings/ApiSettings.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
      useSettingsLayout: true,
    },
  },
  {
    path: '/account/settings/advanced',
    name: 'Advanced Settings',
    components: {
      default: () => import('@/views/account/settings/AdvancedSettings.vue'),
      header: DefaultHeader,
      footer: DefaultFooter,
    },
    meta: {
      requiresAuth: true,
      layoutProps: {
        displayPoweredBy: false,
      },
      useSettingsLayout: true,
    },
  },
  // Legacy route for backward compatibility
  {
    path: '/account/settings/close',
    redirect: '/account/settings/advanced',
  },
];

export default routes;
