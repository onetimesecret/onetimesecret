// src/composables/useCapabilities.ts

import { computed, type Ref } from 'vue';
import type { Organization } from '@/types/organization';
import { CAPABILITIES } from '@/types/organization';

/**
 * Composable for checking organization capabilities
 *
 * @param org - Reactive reference to the organization
 * @returns Functions and computed values for capability checking
 */
export function useCapabilities(org: Ref<Organization | null>) {
  /**
   * Check if the organization has a specific capability
   *
   * @param capability - The capability to check
   * @returns True if the organization has the capability
   */
  const can = (capability: string): boolean => {
    if (!org.value) return false;
    return org.value.capabilities?.includes(capability as any) ?? false;
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
   * Get the upgrade plan needed for a capability
   *
   * @param capability - The capability to check
   * @returns The plan ID needed, or null if already available
   */
  const upgradePath = (capability: string): string | null => {
    if (can(capability)) return null;

    // Map capabilities to required plans
    // This is a simple mapping - in production, this might come from the API
    const capabilityToPlan: Record<string, string> = {
      [CAPABILITIES.CREATE_TEAMS]: 'multi_team_v1',
      [CAPABILITIES.API_ACCESS]: 'multi_team_v1',
      [CAPABILITIES.CUSTOM_DOMAINS]: 'identity_v1',
      [CAPABILITIES.PRIORITY_SUPPORT]: 'identity_v1',
      [CAPABILITIES.AUDIT_LOGS]: 'multi_team_v1',
    };

    return capabilityToPlan[capability] ?? 'identity_v1';
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
   * Computed list of all capabilities
   */
  const capabilities = computed(() => org.value?.capabilities ?? []);

  /**
   * Computed plan ID
   */
  const planId = computed(() => org.value?.planid);

  return {
    can,
    limit,
    upgradePath,
    hasReachedLimit,
    capabilities,
    planId,
    CAPABILITIES,
  };
}
