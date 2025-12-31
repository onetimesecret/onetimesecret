// src/apps/workspace/config/settings-navigation.ts

import { WindowService } from '@/services/window.service';
import type { ComposerTranslation } from 'vue-i18n';

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

/** Billing section navigation (conditionally visible) */
function getBillingSection(t: ComposerTranslation): SettingsNavigationItem {
  return {
    id: 'billing',
    to: '/billing',
    icon: { collection: 'heroicons', name: 'credit-card' },
    label: t('web.billing.overview.title'),
    description: t('web.billing.manage_subscription_and_billing'),
    visible: () => WindowService.get('billing_enabled') === true,
    children: [
      {
        id: 'billing-overview',
        to: '/billing/overview',
        icon: { collection: 'heroicons', name: 'chart-bar' },
        label: t('web.billing.overview.title'),
      },
      {
        id: 'billing-plans',
        to: '/billing/plans',
        icon: { collection: 'heroicons', name: 'sparkles' },
        label: t('web.billing.plans.title'),
      },
      {
        id: 'billing-invoices',
        to: '/billing/invoices',
        icon: { collection: 'heroicons', name: 'document-text' },
        label: t('web.billing.invoices.title'),
      },
    ],
  };
}

/**
 * Generate settings navigation configuration
 * Extracted from SettingsLayout to allow for cleaner architecture
 */
export function getSettingsNavigation(t: ComposerTranslation): SettingsNavigationItem[] {
  // Note: Billing section now has its own route/layout at /billing
  const _billingSection = getBillingSection(t);

  return [
    getProfileSection(t),
    getSecuritySection(t),
    {
      id: 'api',
      to: '/account/settings/api',
      icon: { collection: 'heroicons', name: 'code-bracket' },
      label: t('web.account.api_key'),
      description: t('web.settings.api.manage_api_keys'),
    },
    getRegionSection(t),
    {
      id: 'caution',
      to: '/account/settings/caution',
      icon: { collection: 'heroicons', name: 'cog-6-tooth-solid' },
      label: t('web.settings.caution.title'),
      description: t('web.settings.caution.description'),
    },
  ];
}
