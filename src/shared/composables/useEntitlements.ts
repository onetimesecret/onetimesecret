// src/shared/composables/useEntitlements.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useEntitlementsStore } from '@/shared/stores/entitlementsStore';
import { storeToRefs } from 'pinia';
import type { Organization } from '@/types/organization';
import { ENTITLEMENTS } from '@/types/organization';
import { computed, type Ref } from 'vue';
import { useI18n } from 'vue-i18n';

/**
 * Fallback i18n keys for entitlement display names
 * Used when API data is not available
 */
const FALLBACK_DISPLAY_KEYS: Record<string, string> = {
  [ENTITLEMENTS.API_ACCESS]: 'web.billing.overview.entitlements.api_access',
  [ENTITLEMENTS.CUSTOM_DOMAINS]: 'web.billing.overview.entitlements.custom_domains',
  [ENTITLEMENTS.CUSTOM_PRIVACY_DEFAULTS]: 'web.billing.overview.entitlements.custom_privacy_defaults',
  [ENTITLEMENTS.EXTENDED_DEFAULT_EXPIRATION]: 'web.billing.overview.entitlements.extended_default_expiration',
  [ENTITLEMENTS.CUSTOM_MAIL_SENDER]: 'web.billing.overview.entitlements.custom_mail_sender',
  [ENTITLEMENTS.FLEXIBLE_FROM_DOMAIN]: 'web.billing.overview.entitlements.flexible_from_domain',
  [ENTITLEMENTS.CUSTOM_BRANDING]: 'web.billing.overview.entitlements.custom_branding',
  [ENTITLEMENTS.HOMEPAGE_SECRETS]: 'web.billing.overview.entitlements.homepage_secrets',
  [ENTITLEMENTS.INCOMING_SECRETS]: 'web.billing.overview.entitlements.incoming_secrets',
  [ENTITLEMENTS.MANAGE_ORGS]: 'web.billing.overview.entitlements.manage_orgs',
  [ENTITLEMENTS.MANAGE_TEAMS]: 'web.billing.overview.entitlements.manage_teams',
  [ENTITLEMENTS.MANAGE_MEMBERS]: 'web.billing.overview.entitlements.manage_members',
  [ENTITLEMENTS.MANAGE_SSO]: 'web.billing.overview.entitlements.manage_sso',
  [ENTITLEMENTS.AUDIT_LOGS]: 'web.billing.overview.entitlements.audit_logs',
};

/**
 * Composable for checking organization entitlements
 *
 * @param org - Reactive reference to the organization
 * @returns Functions and computed values for entitlement checking
 */
/* eslint-disable max-lines-per-function */
export function useEntitlements(org: Ref<Organization | null>) {
  const { t } = useI18n();
  const entitlementsStore = useEntitlementsStore();
  const bootstrapStore = useBootstrapStore();
  const { billing_enabled } = storeToRefs(bootstrapStore);

  /**
   * Check if running in standalone mode (all entitlements available)
   * When billing is disabled, full access is granted
   */
  const isStandaloneMode = computed(() => !billing_enabled.value);

  /**
   * Loading state from the entitlements store
   */
  const isLoadingDefinitions = computed(() => entitlementsStore.isLoading);

  /**
   * Error state from the entitlements store
   */
  const definitionsError = computed(() => entitlementsStore.error);

  /**
   * Whether entitlement definitions have been loaded from API
   */
  const hasDefinitions = computed(() => entitlementsStore.isInitialized);

  /**
   * Check if the organization has a specific entitlement
   *
   * @param entitlement - The entitlement to check
   * @returns True if the organization has the entitlement
   */
  const can = (entitlement: string): boolean => {
    // Standalone mode: all entitlements available
    if (isStandaloneMode.value) {
      return true;
    }

    if (!org.value) {
      return false;
    }
    return org.value.entitlements?.includes(entitlement as (typeof ENTITLEMENTS)[keyof typeof ENTITLEMENTS]) ?? false;
  };

  /**
   * Get the limit for a specific resource
   *
   * @param resource - The resource to check (teams, members_per_team, custom_domains)
   * @returns The limit value, or 0 if not set
   */
  const limit = (resource: keyof NonNullable<Organization['limits']>): number => {
    if (!org.value) return 0;
    return org.value.limits?.[resource] ?? 0;
  };

  /**
   * Get the upgrade plan needed for an entitlement
   *
   * Uses API-provided mapping (from entitlementsStore.entitlementToPlanMap).
   * The mapping is dynamically built from the plans returned by the API,
   * ensuring it always reflects current plan offerings.
   *
   * IMPORTANT: Callers must ensure initDefinitions() has been called before
   * using this function. Returns null if definitions aren't loaded.
   *
   * @param entitlement - The entitlement to check
   * @returns The plan ID needed, or null if already available or not loaded
   */
  const upgradePath = (entitlement: string): string | null => {
    // Already has this entitlement - no upgrade needed
    if (can(entitlement)) return null;

    // Warn if definitions not loaded - caller should ensure initDefinitions() ran first
    if (!hasDefinitions.value) {
      console.warn(
        '[useEntitlements] upgradePath called before initDefinitions() completed for:',
        entitlement
      );
      return null;
    }

    // API-driven plan mapping from entitlementsStore
    return entitlementsStore.getRequiredPlan(entitlement);
  };

  /**
   * Check if a limit has been reached
   *
   * @param resource - The resource to check
   * @param current - The current usage
   * @returns True if the limit has been reached
   */
  const hasReachedLimit = (
    resource: keyof NonNullable<Organization['limits']>,
    current: number
  ): boolean => {
    const resourceLimit = limit(resource);
    if (resourceLimit === 0) return false; // No limit set
    return current >= resourceLimit;
  };

  /**
   * Format an entitlement key to a display string using i18n
   * Uses API-provided display_name when available, falls back to hardcoded keys
   *
   * @param entitlementKey - The entitlement key to format
   * @returns The translated display string
   */
  const formatEntitlement = (entitlementKey: string): string => {
    // Try store data first (returns i18n key)
    const storeDisplayName = entitlementsStore.getDisplayName(entitlementKey);

    // If store returned something other than the raw key, use it
    if (storeDisplayName !== entitlementKey) {
      return t(storeDisplayName);
    }

    // Fallback to hardcoded i18n keys
    const fallbackKey = FALLBACK_DISPLAY_KEYS[entitlementKey];
    if (fallbackKey) {
      return t(fallbackKey);
    }

    // Last resort: return the raw key
    return entitlementKey;
  };

  /**
   * Get the i18n key for an entitlement (without translating)
   *
   * @param entitlementKey - The entitlement key
   * @returns The i18n key for the entitlement display name
   */
  const getEntitlementI18nKey = (entitlementKey: string): string => {
    // Try store data first
    const storeDisplayName = entitlementsStore.getDisplayName(entitlementKey);
    if (storeDisplayName !== entitlementKey) {
      return storeDisplayName;
    }

    // Fallback to hardcoded keys
    return FALLBACK_DISPLAY_KEYS[entitlementKey] ?? entitlementKey;
  };

  /**
   * Initialize entitlement definitions from API
   * Call this early in the app lifecycle to populate the store
   */
  const initDefinitions = async (): Promise<void> => {
    await entitlementsStore.init();
  };

  /**
   * Computed list of all entitlements
   */
  const entitlements = computed(() => org.value?.entitlements ?? []);

  /**
   * Computed plan ID
   */
  const planId = computed(() => org.value?.planid);

  return {
    // Core entitlement checking
    can,
    limit,
    upgradePath,
    hasReachedLimit,
    entitlements,
    planId,
    isStandaloneMode,
    ENTITLEMENTS,

    // Formatting
    formatEntitlement,
    getEntitlementI18nKey,

    // Store state
    isLoadingDefinitions,
    definitionsError,
    hasDefinitions,
    initDefinitions,
  };
}
