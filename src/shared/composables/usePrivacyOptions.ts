// src/shared/composables/usePrivacyOptions.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import type { SecretFormData } from './useSecretForm';
import { useSharingControls } from './useSharingControls';

interface LifetimeOption {
  value: number;
  label: string;
}

interface PrivacyOptionsState {
  passphraseVisibility: boolean;
  lifetimeOptions: LifetimeOption[];
}

function includeSelectedTtl(options: number[], selected: number | undefined, maximum: number) {
  if (selected !== undefined && selected >= 60 && selected <= maximum &&
      !options.includes(selected)) {
    options.push(selected);
  }
}

/**
 * usePrivacyOptions - managing privacy-related form options
 *
 * Handles privacy-specific UI logic and data transformations. Manages
 * configurable options based on global limits and provides formatted
 * values for display. Does not maintain state.
 *
 * Responsibilities:
 * - TTL options computation, capped at the ceiling the server enforces for
 *   the current caller (guest vs. plan limit)
 * - Duration formatting
 * - Password visibility
 */

/* eslint-disable max-lines-per-function */
export function usePrivacyOptions(formOperations?: {
  updateField: <K extends keyof SecretFormData>(field: K, value: SecretFormData[K]) => void;
}, selectedTtl?: () => number) {
  const { t } = useI18n();
  const bootstrapStore = useBootstrapStore();
  const { ttlCeiling, defaultTtl } = useSharingControls();

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
      const quotient = seconds / unit.seconds;
      if (Number.isInteger(quotient) && quotient >= 1) {
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
   * Available lifetime options, capped at what the server will actually grant.
   *
   * Anything above the ceiling is dropped: the server silently clamps an
   * over-ceiling anonymous TTL (2026-07-29 API audit, item 4), so offering
   * 30 days against a 7-day grant hands the user a duration they will not
   * get and are never told about.
   */
  const lifetimeOptions = computed<LifetimeOption[]>(() => {
    // Mirrors the server's absolute bound (WithEntitlements::MAX_TTL,
    // 365 days). Real per-caller ceilings arrive via ttlCeiling; this only
    // drops options the server would refuse on any deployment.
    const globalTtl = 3600 * 24 * 365;
    const ceiling = ttlCeiling.value;

    if (ceiling !== null && ceiling < 60) return [];
    const available = (bootstrapStore.secret_options?.ttl_options ?? []).filter(
      (seconds): seconds is number =>
        typeof seconds === 'number' && seconds >= 60 && seconds <= globalTtl
    );

    const usable = ceiling === null ? available : available.filter(seconds => seconds <= ceiling);
    // Include a non-preset ceiling whenever it replaces a longer option.
    if (ceiling !== null && !usable.includes(ceiling) && usable.length < available.length) {
      usable.push(ceiling);
    }
    // Keep the draft visible when switching away from a non-preset ceiling.
    includeSelectedTtl(usable, selectedTtl?.(), Math.min(ceiling ?? globalTtl, globalTtl));

    return usable.map((seconds) => ({
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
    ttlCeiling,
    defaultTtl,

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
