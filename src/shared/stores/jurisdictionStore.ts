// src/shared/stores/jurisdictionStore.ts

import { createError } from '@/shared/composables/useAsyncHandler';
import { PiniaPluginOptions } from '@/plugins/pinia';
import type { Jurisdiction, JurisdictionIcon, RegionsConfig } from '@/schemas/shapes/config';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useApi } from '@/shared/composables/useApi';
import type { PiniaCustomProperties } from 'pinia';
import { defineStore, storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  JURISDICTION_ICONS,
  getJurisdictionIcon,
} from '@/sources/jurisdictions';

// Re-export for backward compatibility
export { JURISDICTION_ICONS, getJurisdictionIcon };

/**
 * Resolve the icon for a jurisdiction, preferring the jurisdiction's own icon
 * if present, otherwise falling back to the identifier mapping.
 */
export function resolveJurisdictionIcon(jurisdiction: Jurisdiction): JurisdictionIcon {
  return jurisdiction.icon ?? getJurisdictionIcon(jurisdiction.identifier);
}

/**
 * Jurisdiction with resolved display_name from i18n and resolved icon.
 */
export interface JurisdictionWithDisplayName extends Jurisdiction {
  display_name: string;
  icon: JurisdictionIcon;
}

/**
 * Resolve display_name from i18n key.
 * Must be called within Vue's setup context.
 */
export function resolveJurisdictionDisplayName(
  jurisdiction: Jurisdiction,
  t: (key: string) => string
): string {
  return t(jurisdiction.display_name_i18n_key);
}

/**
 * Composable that provides jurisdictions with resolved display names.
 * Must be called within Vue's setup context.
 */
export function useJurisdictionDisplayNames() {
  const { t } = useI18n();
  const jurisdictionStore = useJurisdictionStore();

  const resolveDisplayName = (jurisdiction: Jurisdiction): string => t(jurisdiction.display_name_i18n_key);

  const currentJurisdictionWithDisplayName = computed((): JurisdictionWithDisplayName | null => {
    const jurisdiction = jurisdictionStore.getCurrentJurisdiction;
    if (!jurisdiction) return null;
    return {
      ...jurisdiction,
      display_name: resolveDisplayName(jurisdiction),
      icon: resolveJurisdictionIcon(jurisdiction),
    };
  });

  const jurisdictionsWithDisplayName = computed((): JurisdictionWithDisplayName[] => jurisdictionStore.getAllJurisdictions.map((j) => ({
      ...j,
      display_name: resolveDisplayName(j),
      icon: resolveJurisdictionIcon(j),
    })));

  return {
    resolveDisplayName,
    currentJurisdictionWithDisplayName,
    jurisdictionsWithDisplayName,
  };
}

/**
 * N.B.
 * For the time being (i.e. for our first few locations), the region and
 * jurisdiction are the same. EU is EU, US is US. They will differentiate
 * once we get to for example, "California" is US and also California. The
 * reason we make the distinction is that there can be (and are) "layers"
 * of regulations and market forces involved. If I have a business in the
 * US, I probably would prefer to use a US data center given the choice
 * even if the business I'm in is not a regulated industry. I find it
 * helpful to think of it as "compliant by default".
 */

/**
 * Type definition for JurisdictionStore.
 */
export type JurisdictionStore = {
  // State
  enabled: boolean;
  currentJurisdiction: Jurisdiction | null;
  jurisdictions: Jurisdiction[];
  _initialized: boolean;

  // Getters
  getCurrentJurisdiction: Jurisdiction | null;
  getAllJurisdictions: Jurisdiction[];
  getJurisdictionIdentifiers: string[];

  // Actions
  init: () => void;
  findJurisdiction: (identifier: string) => Jurisdiction;
  $reset: () => void;
} & PiniaCustomProperties;

export const useJurisdictionStore = defineStore('jurisdiction', () => {
  const $api = useApi(); // eslint-disable-line
  const bootstrapStore = useBootstrapStore();
  const { regions: bootstrapRegions } = storeToRefs(bootstrapStore);

  // State
  const enabled = ref(false); // originally true
  const currentJurisdiction = ref<Jurisdiction | null>(null);
  const jurisdictions = ref<Jurisdiction[]>([]);
  const _initialized = ref(false);

  // Getters
  const getCurrentJurisdiction = computed(() => currentJurisdiction.value);
  const getAllJurisdictions = computed(() => jurisdictions.value);

  // Actions

  /**
   * Initialize the jurisdiction store with configuration from API
   * Handles both enabled and disabled region scenarios
   */
  interface StoreOptions extends PiniaPluginOptions {
    regions?: RegionsConfig;
  }

  function init(options?: StoreOptions) {
    if (_initialized.value) return;
    const config: RegionsConfig | null | undefined =
      options?.regions ?? bootstrapRegions?.value;

    if (!config) {
      enabled.value = false;
      jurisdictions.value = [];
      currentJurisdiction.value = null;
      _initialized.value = true;
      return;
    }

    enabled.value = config.enabled;
    jurisdictions.value = config.jurisdictions || [];

    // Only find jurisdiction if we have jurisdictions configured
    if (jurisdictions.value.length > 0 && config.current_jurisdiction) {
      const jurisdiction = findJurisdiction(config.current_jurisdiction);
      currentJurisdiction.value = jurisdiction;

      // If regions are disabled, ensure we only have the current jurisdiction
      if (!config.enabled) {
        jurisdictions.value = [jurisdiction];
      }
    } else {
      currentJurisdiction.value = null;
    }

    _initialized.value = true;
  }

  const getJurisdictionIdentifiers = computed((): string[] =>
    jurisdictions.value.map((j) => j.identifier)
  );

  /**
   * Find a jurisdiction by its identifier.
   * @throws ApplicationError if no jurisdiction is found with the given identifier.
   * @param identifier - The identifier of the jurisdiction to find.
   * @returns The found jurisdiction
   */
  function findJurisdiction(identifier: string): Jurisdiction {
    const jurisdiction = jurisdictions.value.find((j) => j.identifier === identifier);

    if (!jurisdiction) {
      throw createError(`Jurisdiction "${identifier}" not found`, 'technical', 'error', {
        identifier,
      });
    }
    return jurisdiction;
  }

  /**
   * Reset store state to initial values
   */
  function $reset() {
    enabled.value = true;
    currentJurisdiction.value = null;
    jurisdictions.value = [];
    _initialized.value = false;
  }

  return {
    // State
    enabled,
    currentJurisdiction,
    jurisdictions,

    // Getters
    getCurrentJurisdiction,
    getAllJurisdictions,
    getJurisdictionIdentifiers,

    // Actions
    init,
    findJurisdiction,
    $reset,
  };
});
