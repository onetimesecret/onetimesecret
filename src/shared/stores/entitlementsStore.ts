// src/shared/stores/entitlementsStore.ts

/**
 * Entitlements Store
 *
 * Manages entitlement definitions and plan mappings fetched from the API.
 * Provides centralized access to:
 * - Entitlement definitions (key, display_name i18n key, category)
 * - Plan definitions (plan_id, name, entitlements list)
 * - Lookup utilities for entitlement-to-plan mapping
 */

import { createApi } from '@/api';
import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

/**
 * Entitlement definition from API
 */
export interface EntitlementDefinition {
  key: string;
  display_name: string; // i18n key e.g., "web.billing.entitlements.api_access"
  category: string;
}

/**
 * Plan definition from API
 */
export interface PlanDefinition {
  plan_id: string;
  name: string;
  entitlements: string[];
}

/**
 * API response shape for entitlements endpoint
 */
export interface EntitlementsApiResponse {
  entitlements: EntitlementDefinition[];
  plans: PlanDefinition[];
}

/* eslint-disable max-lines-per-function */
export const useEntitlementsStore = defineStore('entitlements', () => {
  const $api = createApi();

  // State
  const entitlementDefinitions = ref<EntitlementDefinition[]>([]);
  const planDefinitions = ref<PlanDefinition[]>([]);
  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const _initialized = ref(false);
  const _fetchPromise = ref<Promise<void> | null>(null);

  // Computed: Map of entitlement key -> definition
  const entitlementMap = computed(() => {
    const map = new Map<string, EntitlementDefinition>();
    for (const ent of entitlementDefinitions.value) {
      map.set(ent.key, ent);
    }
    return map;
  });

  // Computed: Map of plan_id -> plan definition
  const planMap = computed(() => {
    const map = new Map<string, PlanDefinition>();
    for (const plan of planDefinitions.value) {
      map.set(plan.plan_id, plan);
    }
    return map;
  });

  // Computed: Map of entitlement key -> minimum plan_id that includes it
  // Plans are assumed to be ordered by tier (lower tier first)
  const entitlementToPlanMap = computed(() => {
    const map = new Map<string, string>();

    // Process plans in order (assumes API returns them in tier order)
    for (const plan of planDefinitions.value) {
      for (const entKey of plan.entitlements) {
        // Only set if not already mapped (first plan with entitlement = minimum tier)
        if (!map.has(entKey)) {
          map.set(entKey, plan.plan_id);
        }
      }
    }
    return map;
  });

  // Getters
  const isInitialized = computed(() => _initialized.value);

  /**
   * Get the i18n display key for an entitlement
   */
  function getDisplayName(entitlementKey: string): string {
    const def = entitlementMap.value.get(entitlementKey);
    return def?.display_name ?? entitlementKey;
  }

  /**
   * Get the category for an entitlement
   */
  function getCategory(entitlementKey: string): string {
    const def = entitlementMap.value.get(entitlementKey);
    return def?.category ?? 'other';
  }

  /**
   * Get the minimum plan required for an entitlement
   */
  function getRequiredPlan(entitlementKey: string): string | null {
    return entitlementToPlanMap.value.get(entitlementKey) ?? null;
  }

  /**
   * Get all entitlements for a plan
   */
  function getPlanEntitlements(planId: string): string[] {
    const plan = planMap.value.get(planId);
    return plan?.entitlements ?? [];
  }

  /**
   * Fetch entitlement definitions from API
   * Uses singleton pattern to prevent duplicate requests
   */
  async function fetch(): Promise<void> {
    // Return existing promise if fetch is in progress
    if (_fetchPromise.value) {
      return _fetchPromise.value;
    }

    // Skip if already initialized and has data
    if (_initialized.value && entitlementDefinitions.value.length > 0) {
      return;
    }

    isLoading.value = true;
    error.value = null;

    _fetchPromise.value = (async () => {
      try {
        const response = await $api.get<EntitlementsApiResponse>('/api/account/entitlements');
        const data = response.data;

        entitlementDefinitions.value = data.entitlements;
        planDefinitions.value = data.plans;
        _initialized.value = true;
      } catch (err) {
        const message = err instanceof Error ? err.message : 'Failed to load entitlement definitions';
        error.value = message;
        console.error('[EntitlementsStore] Error fetching entitlements:', err);
        // Don't throw - allow graceful fallback to hardcoded values
      } finally {
        isLoading.value = false;
        _fetchPromise.value = null;
      }
    })();

    return _fetchPromise.value;
  }

  /**
   * Initialize the store - fetches data if not already loaded
   */
  async function init(): Promise<void> {
    if (!_initialized.value) {
      await fetch();
    }
  }

  /**
   * Reset the store
   */
  function $reset() {
    entitlementDefinitions.value = [];
    planDefinitions.value = [];
    isLoading.value = false;
    error.value = null;
    _initialized.value = false;
    _fetchPromise.value = null;
  }

  return {
    // State
    entitlementDefinitions,
    planDefinitions,
    isLoading,
    error,

    // Computed
    entitlementMap,
    planMap,
    entitlementToPlanMap,
    isInitialized,

    // Actions
    getDisplayName,
    getCategory,
    getRequiredPlan,
    getPlanEntitlements,
    fetch,
    init,
    $reset,
  };
});
