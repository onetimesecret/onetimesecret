// src/apps/workspace/composables/useWorkspacePrivacyDefaults.ts

/**
 * Workspace Privacy Defaults Composable
 *
 * Bridge composable that merges domain-specific brand settings with global
 * secret_options to provide unified privacy defaults for the workspace dashboard.
 *
 * For canonical domains, returns global defaults from secret_options.
 * For custom domains, returns domain-specific brand settings.
 */

import type { BrandSettings } from '@/schemas/models';
import { WindowService } from '@/services/window.service';
import { usePrivacyOptions } from '@/shared/composables/usePrivacyOptions';
import { computed, type ComputedRef, type Ref } from 'vue';

export interface PrivacyDefaults {
  /** Default TTL in seconds, null means use system default */
  defaultTtl: number | null;
  /** Whether passphrase is required */
  passphraseRequired: boolean;
  /** Whether notifications are enabled by default */
  notifyEnabled: boolean;
  /** Whether these are global defaults (canonical domain) vs domain-specific */
  isGlobalDefaults: boolean;
  /** Whether the user can edit these settings (false for canonical domain) */
  isEditable: boolean;
}

export interface UseWorkspacePrivacyDefaultsOptions {
  /** Brand settings from useBranding composable */
  brandSettings: Ref<BrandSettings>;
  /** Whether this is the canonical (default) domain */
  isCanonical: ComputedRef<boolean> | Ref<boolean>;
  /** Whether brand settings are loading */
  isLoading?: Ref<boolean>;
}

export interface UseWorkspacePrivacyDefaultsReturn {
  /** Merged privacy defaults for display */
  privacyDefaults: ComputedRef<PrivacyDefaults>;
  /** Formatted TTL display string */
  ttlDisplay: ComputedRef<string>;
  /** Formatted passphrase status string */
  passphraseDisplay: ComputedRef<string>;
  /** Formatted notify status string */
  notifyDisplay: ComputedRef<string>;
  /** Whether any custom settings are applied (non-default values) */
  hasCustomSettings: ComputedRef<boolean>;
  /** Whether the settings are editable */
  isEditable: ComputedRef<boolean>;
}

/**
 * Composable for managing workspace privacy defaults display.
 *
 * Merges global secret_options with domain-specific brand settings to provide
 * a unified view of privacy defaults for the dashboard privacy bar.
 */
export function useWorkspacePrivacyDefaults(
  options: UseWorkspacePrivacyDefaultsOptions
): UseWorkspacePrivacyDefaultsReturn {
  const { brandSettings, isCanonical } = options;
  const { formatDuration } = usePrivacyOptions();

  // Get global secret options for canonical domain defaults
  const secretOptions = WindowService.get('secret_options');
  const globalDefaultTtl = secretOptions?.default_ttl ?? 604800; // 7 days fallback
  const globalPassphraseRequired = secretOptions?.passphrase?.required ?? false;

  /**
   * Computed privacy defaults that merge global and domain-specific settings
   */
  const privacyDefaults = computed<PrivacyDefaults>(() => {
    if (isCanonical.value) {
      // Canonical domain: use global defaults, not editable
      return {
        defaultTtl: globalDefaultTtl,
        passphraseRequired: globalPassphraseRequired,
        notifyEnabled: false, // Global default for notifications
        isGlobalDefaults: true,
        isEditable: false,
      };
    }

    // Custom domain: use brand settings, editable
    return {
      defaultTtl: brandSettings.value.default_ttl ?? null,
      passphraseRequired: brandSettings.value.passphrase_required ?? false,
      notifyEnabled: brandSettings.value.notify_enabled ?? false,
      isGlobalDefaults: false,
      isEditable: true,
    };
  });

  /**
   * Whether settings are editable (only custom domains)
   */
  const isEditable = computed(() => !isCanonical.value);

  /**
   * Formatted TTL display value
   */
  const ttlDisplay = computed(() => {
    const ttl = privacyDefaults.value.defaultTtl;
    if (ttl === null) {
      return formatDuration(globalDefaultTtl);
    }
    return formatDuration(ttl);
  });

  /**
   * Formatted passphrase status
   */
  const passphraseDisplay = computed(() =>
    privacyDefaults.value.passphraseRequired ? 'required' : 'optional'
  );

  /**
   * Formatted notify status
   */
  const notifyDisplay = computed(() =>
    privacyDefaults.value.notifyEnabled ? 'enabled' : 'disabled'
  );

  /**
   * Whether any non-default settings are applied (for custom domains)
   */
  const hasCustomSettings = computed(() => {
    if (isCanonical.value) return false;

    return (
      brandSettings.value.default_ttl !== null ||
      brandSettings.value.passphrase_required === true ||
      brandSettings.value.notify_enabled === true
    );
  });

  return {
    privacyDefaults,
    ttlDisplay,
    passphraseDisplay,
    notifyDisplay,
    hasCustomSettings,
    isEditable,
  };
}
