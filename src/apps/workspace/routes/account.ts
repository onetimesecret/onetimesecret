// src/apps/workspace/routes/account.ts

import WorkspaceLayout from '@/apps/workspace/layouts/WorkspaceLayout.vue';
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

const routes: Array<RouteRecordRaw> = [
  {
    path: '/account',
    name: 'Account',
    component: () => import('@/apps/workspace/account/settings/ProfileSettings.vue'),
    meta: {
      title: 'web.TITLES.account',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/region',
    name: 'Data Region',
    component: () => import('@/apps/workspace/account/DataRegion.vue'),
    meta: {
      title: 'web.TITLES.data_region',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/region/current',
    name: 'Current Region',
    component: () => import('@/apps/workspace/account/region/CurrentRegion.vue'),
    meta: {
      title: 'web.TITLES.current_region',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/region/available',
    name: 'Available Regions',
    component: () => import('@/apps/workspace/account/region/AvailableRegions.vue'),
    meta: {
      title: 'web.TITLES.available_regions',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/region/why',
    name: 'Why Data Sovereignty Matters',
    component: () => import('@/apps/workspace/account/region/WhyItMatters.vue'),
    meta: {
      title: 'web.TITLES.why_data_sovereignty',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
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
    component: () => import('@/apps/workspace/account/settings/ProfileSettings.vue'),
    meta: {
      title: 'web.TITLES.preferences_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/profile/privacy',
    name: 'Privacy Settings',
    component: () => import('@/apps/workspace/account/settings/PrivacySettings.vue'),
    meta: {
      title: 'web.TITLES.privacy_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/profile/notifications',
    name: 'Notification Settings',
    component: () => import('@/apps/workspace/account/settings/NotificationSettings.vue'),
    meta: {
      title: 'web.TITLES.notification_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/profile/email',
    name: 'Change Email',
    component: () => import('@/apps/workspace/account/settings/ChangeEmail.vue'),
    meta: {
      title: 'web.TITLES.change_email',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/security',
    name: 'Security Overview',
    component: () => import('@/apps/workspace/account/settings/SecurityOverview.vue'),
    meta: {
      title: 'web.TITLES.security_overview',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/security/password',
    name: 'Change Password',
    component: () => import('@/apps/workspace/account/ChangePassword.vue'),
    meta: {
      title: 'web.TITLES.change_password',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/security/mfa',
    name: 'Multi-Factor Authentication',
    component: () => import('@/apps/workspace/account/MfaSettings.vue'),
    meta: {
      title: 'web.TITLES.mfa_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/security/sessions',
    name: 'Active Sessions',
    component: () => import('@/apps/workspace/account/ActiveSessions.vue'),
    meta: {
      title: 'web.TITLES.active_sessions',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/security/recovery-codes',
    name: 'Recovery Codes',
    component: () => import('@/apps/workspace/account/RecoveryCodes.vue'),
    meta: {
      title: 'web.TITLES.recovery_codes',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/security/passkeys',
    name: 'Passkeys',
    component: () => import('@/apps/workspace/account/PasskeySettings.vue'),
    meta: {
      title: 'web.TITLES.passkeys',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/api',
    name: 'API Settings',
    component: () => import('@/apps/workspace/account/settings/ApiSettings.vue'),
    meta: {
      title: 'web.TITLES.api_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/caution',
    name: 'Advanced Settings',
    component: () => import('@/apps/workspace/account/settings/CautionZone.vue'),
    meta: {
      title: 'web.TITLES.advanced_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  // Legacy route for backward compatibility
  {
    path: '/account/settings/close',
    redirect: '/account/settings/caution',
  },
];

export default routes;
