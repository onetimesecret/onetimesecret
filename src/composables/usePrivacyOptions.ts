// src/composables/usePrivacyOptions.ts

import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { WindowService } from '@/services/window.service';
import type { SecretFormData } from './useSecretForm';
import type { SecretOptions } from '@/schemas/config/public';

interface PrivacyConfig {
  secretOptions: SecretOptions;
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
  updateField: <K extends keyof SecretFormData>(field: K, value: SecretFormData[K]) => void;
}) {
  const { t } = useI18n();

  const config: PrivacyConfig = {
    secretOptions: WindowService.get('secret_options'),
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
    // NOTE: this used to be limited based on the plan. We don't bandy that
    // around like we used to so this is just set to the max value for everyone.
    const maxTtl = 3600 * 24 * 30; // 30 days.

    // Get ttl_options from the appropriate user type (fallback to anonymous)
    const userTypeOptions =
      config.secretOptions.anonymous ||
      config.secretOptions.standard ||
      config.secretOptions.enhanced;

    // NOTE: These come from the mutable config now. Is they are saved with
    // null for each of anonymous, standard, enhanced we will be left with
    // an empty array here which currently breaks the secret form altogether
    // b/c it then submits an empty ttl value which is not allowed (also
    // visually the dropdown in the form looks bad empty). In the colonel
    // when saving, we protect against this by validating the input before
    // saving (which applys the defaults defined in zod). If we validate the
    // OnetimeWindow JSON object then we will be able to remove these hardcoded
    // values.
    const ttlOptions = userTypeOptions?.ttl_options || [60, 3600, 86400, 604800, 2592000];

    return ttlOptions
      .filter(
        (seconds): seconds is number =>
          seconds !== null && typeof seconds === 'number' && seconds <= maxTtl
      )
      .map((seconds: number) => ({
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
