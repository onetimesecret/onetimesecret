// src/shared/composables/useEntitlements.ts

import { WindowService } from '@/services/window.service';
import type { Organization } from '@/types/organization';
import { ENTITLEMENTS } from '@/types/organization';
import { computed, type Ref } from 'vue';

/**
 * Composable for checking organization entitlements
 *
 * @param org - Reactive reference to the organization
 * @returns Functions and computed values for entitlement checking
 */
export function useEntitlements(org: Ref<Organization | null>) {
  /**
   * Check if running in standalone mode (all entitlements available)
   * When billing is disabled, full access is granted
   */
  const isStandaloneMode = computed(() => {
    const billingEnabled = WindowService.get('billing_enabled');
    return !billingEnabled;
  });

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
    return org.value.entitlements?.includes(entitlement as any) ?? false;
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
   * Get the upgrade plan needed for a entitlement
   *
   * @param entitlement - The entitlement to check
   * @returns The plan ID needed, or null if already available
   */
  const upgradePath = (entitlement: string): string | null => {
    if (can(entitlement)) return null;

    // Map entitlements to required plans
    // This is a simple mapping - in production, this might come from the API
    const entitlementToPlan: Record<string, string> = {
      [ENTITLEMENTS.MANAGE_TEAMS]: 'identity_v1',
      [ENTITLEMENTS.MANAGE_MEMBERS]: 'identity_v1',
      [ENTITLEMENTS.API_ACCESS]: 'multi_team_v1',
      [ENTITLEMENTS.CUSTOM_DOMAINS]: 'identity_v1',
      [ENTITLEMENTS.PRIORITY_SUPPORT]: 'identity_v1',
      [ENTITLEMENTS.AUDIT_LOGS]: 'multi_team_v1',
    };

    return entitlementToPlan[entitlement] ?? 'identity_v1';
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
   * Computed list of all entitlements
   */
  const entitlements = computed(() => org.value?.entitlements ?? []);

  /**
   * Computed plan ID
   */
  const planId = computed(() => org.value?.planid);

  return {
    can,
    limit,
    upgradePath,
    hasReachedLimit,
    entitlements,
    planId,
    isStandaloneMode,
    ENTITLEMENTS,
  };
}
