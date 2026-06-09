// src/apps/workspace/routes/account.ts

import WorkspaceLayout from '@/apps/workspace/layouts/WorkspaceLayout.vue';
import type { RouteRecordRaw } from 'vue-router';
import { SCOPE_PRESETS } from '@/types/router';
import { hasPassword, isFullAuthMode, isOwnerOrAdmin } from '@/utils/features';

/**
 * Route guard for org-management account routes (password, MFA,
 * recovery codes, passkeys, region, caution). Requires full auth mode
 * AND owner/admin role — regular members' accounts are managed by
 * the org owner.
 */
function checkOwnerOrAdminAccess() {
  if (!isFullAuthMode() || !isOwnerOrAdmin()) {
    return { name: 'Account' };
  }
  return true;
}

/**
 * Route guard for owner/admin routes that also require a password
 * (e.g. Change Email). Members must be reinvited for email changes.
 */
function checkOwnerWithPasswordAccess() {
  if (!isFullAuthMode() || !isOwnerOrAdmin() || !hasPassword()) {
    return { name: 'Account' };
  }
  return true;
}

/**
 * Route guard for password-dependent security routes (password, MFA,
 * recovery codes). Requires full auth mode AND a password-based
 * account. Invited members who set a password see these;
 * SSO-provisioned members (no password) do not.
 */
function checkPasswordSecurityAccess() {
  if (!isFullAuthMode() || !hasPassword()) {
    return { name: 'Account' };
  }
  return true;
}

/**
 * Route guard for security routes accessible to all authenticated
 * users (Security Overview, Active Sessions).
 */
function checkSecurityAccess() {
  if (!isFullAuthMode()) {
    return { name: 'Account' };
  }
  return true;
}

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
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/region',
    name: 'Data Region',
    beforeEnter: checkOwnerOrAdminAccess,
    component: () => import('@/apps/workspace/account/DataRegion.vue'),
    meta: {
      title: 'web.TITLES.data_region',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/region/current',
    name: 'Current Region',
    beforeEnter: checkOwnerOrAdminAccess,
    component: () => import('@/apps/workspace/account/region/CurrentRegion.vue'),
    meta: {
      title: 'web.TITLES.current_region',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/region/available',
    name: 'Available Regions',
    beforeEnter: checkOwnerOrAdminAccess,
    component: () => import('@/apps/workspace/account/region/AvailableRegions.vue'),
    meta: {
      title: 'web.TITLES.available_regions',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/region/why',
    name: 'Why Data Sovereignty Matters',
    beforeEnter: checkOwnerOrAdminAccess,
    component: () => import('@/apps/workspace/account/region/WhyItMatters.vue'),
    meta: {
      title: 'web.TITLES.why_data_sovereignty',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
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
      sentryScrubParams: false,
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
      sentryScrubParams: false,
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
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/settings/profile/email',
    name: 'Change Email',
    beforeEnter: checkOwnerWithPasswordAccess,
    component: () => import('@/apps/workspace/account/settings/ChangeEmail.vue'),
    meta: {
      title: 'web.TITLES.change_email',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  // NOTE: /account/email/confirm/:token uses default sentryScrubParams (scrub all)
  // because the token is sensitive
  {
    path: '/account/email/confirm/:token',
    name: 'Confirm Email Change',
    component: () => import(
      '@/apps/workspace/account/settings/ConfirmEmailChange.vue'
    ),
    meta: {
      title: 'web.TITLES.confirm_email_change',
      requiresAuth: false,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
    },
  },
  {
    path: '/account/settings/security',
    name: 'Security Overview',
    beforeEnter: checkSecurityAccess,
    component: () => import('@/apps/workspace/account/settings/SecurityOverview.vue'),
    meta: {
      title: 'web.TITLES.security_overview',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/settings/security/password',
    name: 'Change Password',
    beforeEnter: checkPasswordSecurityAccess,
    component: () => import('@/apps/workspace/account/ChangePassword.vue'),
    meta: {
      title: 'web.TITLES.change_password',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/settings/security/reset-password',
    name: 'Reset Password',
    beforeEnter: checkPasswordSecurityAccess,
    component: () => import('@/apps/workspace/account/ResetPassword.vue'),
    meta: {
      title: 'web.TITLES.reset_password',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/settings/security/mfa',
    name: 'Multi-Factor Authentication',
    beforeEnter: checkPasswordSecurityAccess,
    component: () => import('@/apps/workspace/account/MfaSettings.vue'),
    meta: {
      title: 'web.TITLES.mfa_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/settings/security/sessions',
    name: 'Active Sessions',
    beforeEnter: checkSecurityAccess,
    component: () => import('@/apps/workspace/account/ActiveSessions.vue'),
    meta: {
      title: 'web.TITLES.active_sessions',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/settings/security/recovery-codes',
    name: 'Recovery Codes',
    beforeEnter: checkPasswordSecurityAccess,
    component: () => import('@/apps/workspace/account/RecoveryCodes.vue'),
    meta: {
      title: 'web.TITLES.recovery_codes',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/settings/security/passkeys',
    name: 'Passkeys',
    beforeEnter: checkSecurityAccess,
    component: () => import('@/apps/workspace/account/PasskeySettings.vue'),
    meta: {
      title: 'web.TITLES.passkeys',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
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
      sentryScrubParams: false,
    },
  },
  {
    path: '/account/settings/caution',
    name: 'Advanced Settings',
    beforeEnter: checkOwnerOrAdminAccess,
    component: () => import('@/apps/workspace/account/settings/CautionZone.vue'),
    meta: {
      title: 'web.TITLES.advanced_settings',
      requiresAuth: true,
      layout: WorkspaceLayout,
      layoutProps: standardLayoutProps,
      scopesAvailable: SCOPE_PRESETS.hideBoth,
      sentryScrubParams: false,
    },
  },
  // Legacy route for backward compatibility
  {
    path: '/account/settings/close',
    redirect: '/account/settings/caution',
  },
];

export default routes;
