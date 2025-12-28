// src/shared/composables/useEntitlements.ts

import { WindowService } from '@/services/window.service';
import { useEntitlementsStore } from '@/shared/stores/entitlementsStore';
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
  [ENTITLEMENTS.CUSTOM_MAIL_DEFAULTS]: 'web.billing.overview.entitlements.custom_mail_defaults',
  [ENTITLEMENTS.CUSTOM_BRANDING]: 'web.billing.overview.entitlements.custom_branding',
  [ENTITLEMENTS.BRANDED_HOMEPAGE]: 'web.billing.overview.entitlements.branded_homepage',
  [ENTITLEMENTS.INCOMING_SECRETS]: 'web.billing.overview.entitlements.incoming_secrets',
  [ENTITLEMENTS.MANAGE_ORGS]: 'web.billing.overview.entitlements.manage_orgs',
  [ENTITLEMENTS.MANAGE_TEAMS]: 'web.billing.overview.entitlements.manage_teams',
  [ENTITLEMENTS.MANAGE_MEMBERS]: 'web.billing.overview.entitlements.manage_members',
  [ENTITLEMENTS.AUDIT_LOGS]: 'web.billing.overview.entitlements.audit_logs',
};

/**
 * Fallback entitlement to plan mapping
 * ONLY used when API data has not been loaded yet.
 * Once initDefinitions() is called and succeeds, the store's dynamic
 * entitlementToPlanMap (built from API response) takes precedence.
 *
 * @deprecated Prefer calling initDefinitions() early in the app lifecycle
 * to use API-driven plan mappings instead of these hardcoded values.
 */
const FALLBACK_ENTITLEMENT_TO_PLAN: Record<string, string> = {
  [ENTITLEMENTS.MANAGE_TEAMS]: 'identity_v1',
  [ENTITLEMENTS.MANAGE_MEMBERS]: 'identity_v1',
  [ENTITLEMENTS.MANAGE_ORGS]: 'identity_v1',
  [ENTITLEMENTS.API_ACCESS]: 'identity_v1',
  [ENTITLEMENTS.CUSTOM_DOMAINS]: 'identity_v1',
  [ENTITLEMENTS.CUSTOM_BRANDING]: 'identity_v1',
  [ENTITLEMENTS.BRANDED_HOMEPAGE]: 'identity_v1',
  [ENTITLEMENTS.CUSTOM_PRIVACY_DEFAULTS]: 'identity_v1',
  [ENTITLEMENTS.EXTENDED_DEFAULT_EXPIRATION]: 'identity_v1',
  [ENTITLEMENTS.CUSTOM_MAIL_DEFAULTS]: 'identity_v1',
  [ENTITLEMENTS.INCOMING_SECRETS]: 'identity_v1',
  [ENTITLEMENTS.AUDIT_LOGS]: 'multi_team_v1',
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

  /**
   * Check if running in standalone mode (all entitlements available)
   * When billing is disabled, full access is granted
   */
  const isStandaloneMode = computed(() => {
    const billingEnabled = WindowService.get('billing_enabled');
    return !billingEnabled;
  });

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
    if (isStandaloneMode.value) return true;

    if (!org.value) return false;
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
   * Uses API-provided mapping (from entitlementsStore.entitlementToPlanMap)
   * when available. The mapping is dynamically built from the plans returned
   * by the API, ensuring it always reflects current plan offerings.
   *
   * Falls back to hardcoded values ONLY when:
   * - initDefinitions() has not been called yet
   * - The API request failed
   * - The entitlement is not in any plan's entitlements list
   *
   * @param entitlement - The entitlement to check
   * @returns The plan ID needed, or null if already available
   */
  const upgradePath = (entitlement: string): string | null => {
    // Already has this entitlement - no upgrade needed
    if (can(entitlement)) return null;

    // Primary source: API-driven plan mapping from entitlementsStore
    // The store builds entitlementToPlanMap dynamically from API response
    const storePlan = entitlementsStore.getRequiredPlan(entitlement);
    if (storePlan) {
      return storePlan;
    }

    // Fallback: Only used when store hasn't loaded or doesn't have the mapping
    // This ensures the UI remains functional before API responds
    if (!hasDefinitions.value) {
      console.debug(
        '[useEntitlements] Using fallback plan mapping for:',
        entitlement,
        '- call initDefinitions() for API-driven values'
      );
    }
    return FALLBACK_ENTITLEMENT_TO_PLAN[entitlement] ?? null;
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
