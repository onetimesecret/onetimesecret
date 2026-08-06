// src/shared/composables/usePrivacyOptions.ts

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import type { SecretFormData } from './useSecretForm';

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
}) {
  const { t } = useI18n();
  const bootstrapStore = useBootstrapStore();
  // organization stays on the store: it is an optional payload field, so
  // storeToRefs types the ref itself as possibly undefined.
  const { secret_options, authenticated } = storeToRefs(bootstrapStore);

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
   * TTL ceiling the server will enforce for the current caller, in seconds.
   *
   * `null` means "no ceiling is knowable" and the dropdown falls open to the
   * configured ttl_options — an org with no plan limit, or a bootstrap payload
   * that predates these fields.
   *
   * Mirrors the max_ttl ladder in V2 BaseSecretAction#process_ttl:
   *   authenticated + org -> limits.secret_lifetime
   *   anonymous           -> ttl_max_anonymous
   *   otherwise           -> config ttl_options max
   *
   * Note the anonymous ceiling is a hard product rule (7 days,
   * WithEntitlements::ANONYMOUS_MAX_TTL) that the server applies on every
   * deployment, so the serializer always sends it. Do not restate the number
   * here — read what was sent.
   */
  const ttlCeiling = computed<number | null>(() => {
    const positiveOrNull = (value: number | null | undefined) =>
      typeof value === 'number' && value > 0 ? value : null;

    if (authenticated.value) {
      // No org means the server never consults a plan limit, so neither do we.
      // -1 (unlimited) and 0 (unset) both fall through to null.
      const organization = bootstrapStore.organization;
      return organization ? positiveOrNull(organization.limits?.secret_lifetime) : null;
    }

    return positiveOrNull(secret_options.value?.ttl_max_anonymous);
  });

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

    const available = (secret_options.value?.ttl_options ?? []).filter(
      (seconds): seconds is number =>
        seconds !== null && typeof seconds === 'number' && seconds <= globalTtl
    );

    let usable = ceiling === null ? available : available.filter((seconds) => seconds <= ceiling);

    // A ceiling below every configured option would leave the selector with
    // nothing to render and WorkspaceSecretForm with no valid preferred TTL.
    // Keep the shortest option instead of an empty list; the server clamps it
    // down to the ceiling from there.
    if (usable.length === 0 && available.length > 0) {
      usable = [Math.min(...available)];
    }

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
