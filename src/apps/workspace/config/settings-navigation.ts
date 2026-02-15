// src/apps/workspace/config/settings-navigation.ts

import type { ComposerTranslation } from 'vue-i18n';
import { isFullAuthMode, isWebAuthnEnabled } from '@/utils/features';

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
function getProfileSection(t: ComposerTranslation): SettingsNavigationItem {
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

/** Security section navigation */
function getSecuritySection(t: ComposerTranslation): SettingsNavigationItem {
  return {
    id: 'security',
    to: '/account/settings/security',
    icon: { collection: 'heroicons', name: 'shield-check-solid' },
    label: t('web.COMMON.security'),
    description: t('web.settings.security_settings_description'),
    visible: () => isFullAuthMode(),
    children: [
      {
        id: 'password',
        to: '/account/settings/security/password',
        icon: { collection: 'heroicons', name: 'lock-closed-solid' },
        label: t('web.auth.change_password.title'),
      },
      {
        id: 'mfa',
        to: '/account/settings/security/mfa',
        icon: { collection: 'heroicons', name: 'key-solid' },
        label: t('web.auth.mfa.title'),
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
      },
      {
        id: 'passkeys',
        to: '/account/settings/security/passkeys',
        icon: { collection: 'heroicons', name: 'finger-print-solid' },
        label: t('web.auth.passkeys.title'),
        visible: () => isWebAuthnEnabled(),
      },
    ],
  };
}

/** Region section navigation */
function getRegionSection(t: ComposerTranslation): SettingsNavigationItem {
  return {
    id: 'region',
    to: '/account/region',
    icon: { collection: 'heroicons', name: 'globe-alt-solid' },
    label: t('web.account.region'),
    description: t('web.regions.data_sovereignty_title'),
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
export function getSettingsNavigation(t: ComposerTranslation): SettingsNavigationItem[] {
  const sections = getSettingsNavigationSections(t);
  return sections.flatMap((section) =>
    section.visible === undefined || section.visible() ? section.items : []
  );
}

/**
 * Generate grouped settings navigation configuration
 * Returns sections with their navigation items for sidebar rendering
 */
export function getSettingsNavigationSections(t: ComposerTranslation): SettingsNavigationSection[] {
  return [
    {
      id: 'account',
      label: t('web.settings.sections.account'),
      items: [
        getProfileSection(t),
        getSecuritySection(t),
        {
          id: 'api',
          to: '/account/settings/api',
          icon: { collection: 'heroicons', name: 'code-bracket' },
          label: t('web.account.api_key'),
          description: t('web.settings.api.manage_api_keys'),
          // Hidden until API key functionality is complete for launch
          visible: () => false,
        },
      ],
    },
    {
      id: 'advanced',
      label: t('web.settings.sections.advanced'),
      items: [
        getRegionSection(t),
        {
          id: 'caution',
          to: '/account/settings/caution',
          // no-symbol: Reserved exclusively for destructive/irreversible actions
          icon: { collection: 'heroicons', name: 'no-symbol-solid' },
          label: t('web.settings.caution.title'),
          description: t('web.settings.caution.description'),
        },
      ],
    },
  ];
}
