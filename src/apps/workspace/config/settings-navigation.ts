// src/apps/workspace/config/settings-navigation.ts
//
// Tab/section visibility matrix — the spec that visible() callbacks implement.
// Route guards in account.ts mirror these gates as a secondary enforcement layer.
//
// ┌──────────────────┬────────────────────┬──────────┬──────────┬──────────┬──────────┬─────────────┬─────────────┐
// │ Tab / Section    │ Gate               │ Owner pw │ Owner SSO│ Admin pw │ Admin SSO│ Member inv. │ Member SSO  │
// ├──────────────────┼────────────────────┼──────────┼──────────┼──────────┼──────────┼─────────────┼─────────────┤
// │ Profile          │ —                  │ ✓        │ ✓        │ ✓        │ ✓        │ ✓           │ ✓           │
// │  └ Change Email  │ isOwnerOrAdmin     │ ✓        │ —        │ ✓        │ —        │ —           │ —           │
// │                  │ + hasPassword      │          │          │          │          │             │             │
// │ Security section │ isFullAuthMode     │ ✓        │ ✓        │ ✓        │ ✓        │ ✓           │ ✓           │
// │  ├ Password      │ hasPassword        │ ✓        │ —        │ ✓        │ —        │ ✓           │ —           │
// │  ├ MFA           │ hasPassword        │ ✓        │ —        │ ✓        │ —        │ ✓           │ —           │
// │  ├ Sessions      │ —                  │ ✓        │ ✓        │ ✓        │ ✓        │ ✓           │ ✓           │
// │  ├ Recovery      │ hasPassword        │ ✓        │ —        │ ✓        │ —        │ ✓           │ —           │
// │  └ Passkeys      │ isWebAuthnEnabled  │ ✓        │ ✓        │ ✓        │ ✓        │ ✓           │ ✓           │
// │ API              │ —                  │ ✓        │ ✓        │ ✓        │ ✓        │ ✓           │ ✓           │
// │ Region           │ isOwnerOrAdmin     │ ✓*       │ ✓*       │ ✓*       │ ✓*       │ —           │ —           │
// │ Caution          │ isOwnerOrAdmin     │ ✓*       │ ✓*       │ ✓*       │ ✓*       │ —           │ —           │
// │                  │                    │          │          │          │          │             │             │
// │ * also requires isFullAuthMode        │          │          │          │          │             │             │
// └──────────────────┴────────────────────┴──────────┴──────────┴──────────┴──────────┴─────────────┴─────────────┘

import { hasPassword, isFullAuthMode, isSsoOnlyMode, isOwnerOrAdmin, isWebAuthnEnabled } from '@/utils/features';
import type { ComposerTranslation } from 'vue-i18n';

/**
 * Resolved feature flags that drive section/item visibility.
 *
 * Callers in reactive contexts (Vue computeds reading the bootstrap Pinia
 * store) should derive these via the `*Of` helpers in `@/utils/features`
 * and pass them in. When omitted, this module falls back to the
 * snapshot-reading wrappers — used by tests and any non-reactive callers.
 */
export interface NavigationFeatures {
  hasPassword: boolean;
  isFullAuthMode: boolean;
  isSsoOnlyMode: boolean;
  isOwnerOrAdmin: boolean;
  isWebAuthnEnabled: boolean;
}

function resolveFeatures(features?: NavigationFeatures): NavigationFeatures {
  return (
    features ?? {
      hasPassword: hasPassword(),
      isFullAuthMode: isFullAuthMode(),
      isSsoOnlyMode: isSsoOnlyMode(),
      isOwnerOrAdmin: isOwnerOrAdmin(),
      isWebAuthnEnabled: isWebAuthnEnabled(),
    }
  );
}

/**
 * Icon configuration for navigation items
 */
export interface IconConfig {
  collection: string;
  name: string;
}

/**
 * Navigation item for settings sidebar
 */
export interface SettingsNavigationItem {
  id: string;
  to: string;
  icon: IconConfig;
  label: string;
  description?: string;
  badge?: string;
  children?: SettingsNavigationItem[];
  visible?: () => boolean;
}

/**
 * Section group containing navigation items
 */
export interface SettingsNavigationSection {
  id: string;
  label: string;
  items: SettingsNavigationItem[];
  visible?: () => boolean;
}

/** Profile section navigation */
function getProfileSection(t: ComposerTranslation, f: NavigationFeatures): SettingsNavigationItem {
  return {
    id: 'profile',
    to: '/account/settings/profile',
    icon: { collection: 'heroicons', name: 'user-solid' },
    label: t('web.settings.profile.title'),
    description: t('web.settings.profile_settings_description'),
    children: [
      {
        id: 'preferences',
        to: '/account/settings/profile/preferences',
        icon: { collection: 'heroicons', name: 'adjustments-horizontal-solid' },
        label: t('web.settings.preferences'),
      },
      {
        id: 'privacy',
        to: '/account/settings/profile/privacy',
        icon: { collection: 'heroicons', name: 'shield-check' },
        label: t('web.settings.privacy.title'),
      },
      {
        id: 'email',
        to: '/account/settings/profile/email',
        icon: { collection: 'heroicons', name: 'envelope' },
        label: t('web.settings.profile.change_email'),
        visible: () => f.isOwnerOrAdmin && f.hasPassword,
      },
      {
        id: 'notifications',
        to: '/account/settings/profile/notifications',
        icon: { collection: 'heroicons', name: 'bell-solid' },
        label: t('web.settings.notifications.title'),
      },
    ],
  };
}

/**
 * Security section navigation
 *
 * The section is visible to all authenticated users in full-auth mode so
 * that regular members can access Sessions. Password-dependent sub-tabs
 * (password, MFA, recovery codes) are gated by hasPassword — visible to
 * any user who set a password (owners, admins, or invited members).
 * Passkeys are gated by the webauthn feature flag independently.
 */
function getSecuritySection(
  t: ComposerTranslation,
  f: NavigationFeatures
): SettingsNavigationItem {
  return {
    id: 'security',
    to: '/account/settings/security',
    icon: { collection: 'heroicons', name: 'shield-check-solid' },
    label: t('web.COMMON.security'),
    description: t('web.settings.security_settings_description'),
    visible: () => f.isFullAuthMode,
    children: [
      {
        id: 'password',
        to: '/account/settings/security/password',
        icon: { collection: 'heroicons', name: 'lock-closed-solid' },
        label: t('web.auth.change_password.title'),
        visible: () => f.hasPassword,
      },
      {
        id: 'mfa',
        to: '/account/settings/security/mfa',
        icon: { collection: 'heroicons', name: 'key-solid' },
        label: t('web.auth.mfa.title'),
        visible: () => f.hasPassword,
      },
      {
        id: 'sessions',
        to: '/account/settings/security/sessions',
        icon: { collection: 'heroicons', name: 'computer-desktop-solid' },
        label: t('web.auth.sessions.title'),
      },
      {
        id: 'recovery-codes',
        to: '/account/settings/security/recovery-codes',
        icon: { collection: 'heroicons', name: 'document-text-solid' },
        label: t('web.auth.recovery_codes.title'),
        visible: () => f.hasPassword,
      },
      {
        id: 'passkeys',
        to: '/account/settings/security/passkeys',
        icon: { collection: 'heroicons', name: 'finger-print-solid' },
        label: t('web.auth.passkeys.title'),
        visible: () => f.isWebAuthnEnabled,
      },
    ],
  };
}

/** Region section navigation */
function getRegionSection(
  t: ComposerTranslation,
  f: NavigationFeatures
): SettingsNavigationItem {
  return {
    id: 'region',
    to: '/account/region',
    icon: { collection: 'heroicons', name: 'globe-alt-solid' },
    label: t('web.account.region'),
    description: t('web.regions.data_sovereignty_title'),
    visible: () => f.isFullAuthMode && f.isOwnerOrAdmin,
    children: [
      {
        id: 'current',
        to: '/account/region/current',
        icon: { collection: 'heroicons', name: 'map-pin' },
        label: t('web.regions.your_region'),
      },
      {
        id: 'available',
        to: '/account/region/available',
        icon: { collection: 'heroicons', name: 'globe-americas-solid' },
        label: t('web.regions.available_regions'),
      },
      {
        id: 'why',
        to: '/account/region/why',
        icon: { collection: 'heroicons', name: 'shield-check-solid' },
        label: t('web.regions.why_it_matters'),
      },
    ],
  };
}

/**
 * Generate flat settings navigation configuration (legacy)
 * @deprecated Use getSettingsNavigationSections for grouped navigation
 */
export function getSettingsNavigation(
  t: ComposerTranslation,
  features?: NavigationFeatures
): SettingsNavigationItem[] {
  const sections = getSettingsNavigationSections(t, features);
  return sections.flatMap((section) =>
    section.visible === undefined || section.visible() ? section.items : []
  );
}

/**
 * Generate grouped settings navigation configuration.
 * Returns sections with their navigation items for sidebar rendering.
 *
 * @param t - i18n translator
 * @param features - resolved feature flags (provide reactive values to make
 *   the resulting `visible()` callbacks responsive to bootstrap state changes
 *   without re-mounting the consumer). Omit to fall back to the snapshot-based
 *   wrappers in `@/utils/features`.
 */
export function getSettingsNavigationSections(
  t: ComposerTranslation,
  features?: NavigationFeatures
): SettingsNavigationSection[] {
  const f = resolveFeatures(features);
  return [
    {
      id: 'account',
      label: t('web.settings.sections.account'),
      items: [
        getProfileSection(t, f),
        getSecuritySection(t, f),
        {
          id: 'api',
          to: '/account/settings/api',
          icon: { collection: 'heroicons', name: 'code-bracket' },
          label: t('web.account.api_key'),
          description: t('web.settings.api.manage_api_keys'),
          visible: () => true,
        },
      ],
    },
    {
      id: 'advanced',
      label: t('web.settings.sections.advanced'),
      items: [
        getRegionSection(t, f),
        {
          id: 'caution',
          to: '/account/settings/caution',
          // no-symbol: Reserved exclusively for destructive/irreversible actions
          icon: { collection: 'heroicons', name: 'no-symbol-solid' },
          label: t('web.settings.caution.title'),
          description: t('web.settings.caution.description'),
          visible: () => f.isFullAuthMode && f.isOwnerOrAdmin,
        },
      ],
    },
  ];
}
