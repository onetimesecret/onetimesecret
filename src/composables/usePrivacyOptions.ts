// src/composables/usePrivacyOptions.ts

import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { WindowService } from '@/services/window.service';

const plan = WindowService.get('plan');
const secretOptions = WindowService.get('secret_options') ?? {
  ttl: 7200,
  ttl_options: [],
};

interface LifetimeOption {
  value: string;
  label: string;
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
export function usePrivacyOptions() {
  const { t } = useI18n();

  /**
   * Formats the duration from seconds to a human-readable string.
   * @param {number} seconds - The duration in seconds.
   * @returns {string} - The formatted duration string.
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
    const planTtl = plan?.options?.ttl || 0;

    return (secretOptions.ttl_options as number[])
      .filter((seconds) => seconds <= planTtl)
      .map((seconds) => ({
        value: seconds.toString(),
        label: formatDuration(seconds),
      }));
  });

  /**
   * Password visibility state management
   */
  const passphraseVisibility = ref(false);
  const togglePassphraseVisibility = () => {
    passphraseVisibility.value = !passphraseVisibility.value;
  };

  return {
    lifetimeOptions,
    passphraseVisibility,
    togglePassphraseVisibility,
    formatDuration,
  };
}
