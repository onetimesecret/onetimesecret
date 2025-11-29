// src/router/account.routes.ts

import {
  ImprovedFooter,
  ImprovedHeader,
  ImprovedLayout,
  standardLayoutProps,
} from './layout.config';
import { RouteRecordRaw } from 'vue-router';

const routes: Array<RouteRecordRaw> = [
  {
    path: '/account',
    name: 'Account',
    components: {
      default: () => import('@/views/account/settings/ProfileSettings.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.account',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/region',
    name: 'Data Region',
    components: {
      default: () => import('@/views/account/DataRegion.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.data_region',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/region/current',
    name: 'Current Region',
    components: {
      default: () => import('@/views/account/region/CurrentRegion.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.current_region',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/region/available',
    name: 'Available Regions',
    components: {
      default: () => import('@/views/account/region/AvailableRegions.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.available_regions',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/region/why',
    name: 'Why Data Sovereignty Matters',
    components: {
      default: () => import('@/views/account/region/WhyItMatters.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.why_data_sovereignty',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/settings',
    redirect: '/account/settings/profile/preferences',
  },
  {
    path: '/account/settings/profile',
    redirect: '/account/settings/profile/preferences',
  },
  {
    path: '/account/settings/profile/preferences',
    name: 'Preferences Settings',
    components: {
      default: () => import('@/views/account/settings/ProfileSettings.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.preferences_settings',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/settings/profile/privacy',
    name: 'Privacy Settings',
    components: {
      default: () => import('@/views/account/settings/PrivacySettings.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.privacy_settings',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/settings/profile/email',
    name: 'Change Email',
    components: {
      default: () => import('@/views/account/settings/ChangeEmail.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.change_email',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/settings/security',
    name: 'Security Overview',
    components: {
      default: () => import('@/views/account/settings/SecurityOverview.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.security_overview',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/settings/security/password',
    name: 'Change Password',
    components: {
      default: () => import('@/views/account/ChangePassword.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.change_password',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/settings/security/mfa',
    name: 'Multi-Factor Authentication',
    components: {
      default: () => import('@/views/account/MfaSettings.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.mfa_settings',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/settings/security/sessions',
    name: 'Active Sessions',
    components: {
      default: () => import('@/views/account/ActiveSessions.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.active_sessions',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/settings/security/recovery-codes',
    name: 'Recovery Codes',
    components: {
      default: () => import('@/views/account/RecoveryCodes.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.recovery_codes',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/settings/api',
    name: 'API Settings',
    components: {
      default: () => import('@/views/account/settings/ApiSettings.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.api_settings',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  {
    path: '/account/settings/caution',
    name: 'Advanced Settings',
    components: {
      default: () => import('@/views/account/settings/CautionZone.vue'),
      header: ImprovedHeader,
      footer: ImprovedFooter,
    },
    meta: {
      title: 'web.TITLES.advanced_settings',
      requiresAuth: true,
      layout: ImprovedLayout,
      layoutProps: standardLayoutProps,
    },
  },
  // Legacy route for backward compatibility
  {
    path: '/account/settings/close',
    redirect: '/account/settings/caution',
  },
];

export default routes;
