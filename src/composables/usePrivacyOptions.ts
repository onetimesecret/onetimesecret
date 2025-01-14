// src/composables/usePrivacyOptions.ts

import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { WindowService } from '@/services/window.service';
import type { SecretFormData } from './useSecretForm';

interface PrivacyConfig {
  plan: {
    options: {
      ttl: number;
    };
  } | null;
  secretOptions: {
    ttl: number;
    ttl_options: number[];
  };
}

interface LifetimeOption {
  value: number;
  label: string;
}

interface PrivacyOptionsState {
  passphraseVisibility: boolean;
  lifetimeOptions: LifetimeOption[];
}

/**
 * usePrivacyOptions - managing privacy-related form options
 *
 * Handles privacy-specific UI logic and data transformations. Manages
 * configurable options based on user plan limits and provides formatted
 * values for display. Does not maintain state.
 *
 * Responsibilities:
 * - TTL options computation
 * - Duration formatting
 * - Password visibility
 * - Plan-aware filtering
 */
/* eslint-disable max-lines-per-function */
export function usePrivacyOptions(formOperations?: {
  updateField: <K extends keyof SecretFormData>(
    field: K,
    value: SecretFormData[K]
  ) => void;
}) {
  const { t } = useI18n();

  // Configuration
  const config: PrivacyConfig = {
    plan: WindowService.get('plan'),
    secretOptions: WindowService.get('secret_options') ?? {
      ttl: 7200,
      ttl_options: [],
    },
  };

  // UI State
  const state = ref<PrivacyOptionsState>({
    passphraseVisibility: false,
    lifetimeOptions: [],
  });

  /**
   * Formats duration for display
   */
  const formatDuration = (seconds: number): string => {
    const units = [
      { key: 'day', seconds: 86400 },
      { key: 'hour', seconds: 3600 },
      { key: 'minute', seconds: 60 },
      { key: 'second', seconds: 1 },
    ];

    for (const unit of units) {
      const quotient = Math.floor(seconds / unit.seconds);
      if (quotient >= 1) {
        return t('web.UNITS.ttl.duration', {
          count: quotient,
          unit: t(`web.UNITS.ttl.time.${unit.key}`, quotient),
        });
      }
    }

    return t('web.UNITS.ttl.duration', {
      count: seconds,
      unit: t('web.UNITS.ttl.time.second', seconds),
    });
  };

  /**
   * Available lifetime options based on plan limits
   */
  const lifetimeOptions = computed<LifetimeOption[]>(() => {
    const planTtl = config.plan?.options?.ttl || 0;

    return config.secretOptions.ttl_options
      .filter((seconds) => seconds <= planTtl)
      .map((seconds) => ({
        value: seconds,
        label: formatDuration(seconds),
      }));
  });

  // Field Updates
  const updatePassphrase = (value: string) => {
    formOperations?.updateField('passphrase', value);
  };

  const updateTtl = (value: number) => {
    formOperations?.updateField('ttl', value);
  };

  const updateRecipient = (value: string) => {
    formOperations?.updateField('recipient', value);
  };

  // UI Actions
  const togglePassphraseVisibility = () => {
    state.value.passphraseVisibility = !state.value.passphraseVisibility;
  };

  return {
    // State
    state,
    lifetimeOptions,

    // Field Updates
    updatePassphrase,
    updateTtl,
    updateRecipient,

    // UI Actions
    togglePassphraseVisibility,

    // Utilities
    formatDuration,
  };
}
