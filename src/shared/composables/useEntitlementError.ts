// src/shared/composables/useEntitlementError.ts

import type { ApplicationError } from '@/schemas/errors';
import { computed } from 'vue';

/**
 * API error response structure for entitlement/upgrade errors
 */
export interface EntitlementErrorDetails {
  error_type?: string;
  field?: string;
  details?: Record<string, unknown>;
}

/**
 * Composable for detecting and extracting entitlement upgrade error information
 * from API error responses.
 *
 * @param error - The ApplicationError or unknown error object
 * @returns Object with helpers to identify upgrade-required errors
 *
 * @example
 * ```ts
 * const { isUpgradeRequired, errorMessage, field } = useEntitlementError(error);
 *
 * if (isUpgradeRequired.value) {
 *   // Show upgrade prompt
 * }
 * ```
 */
export function useEntitlementError(error: ApplicationError | unknown | null) {
  const isUpgradeRequired = computed(() => {
    if (!error || typeof error !== 'object') return false;

    const appError = error as ApplicationError;
    const details = appError.details as EntitlementErrorDetails | undefined;

    return details?.error_type === 'upgrade_required';
  });

  const errorMessage = computed(() => {
    if (!error || typeof error !== 'object') return '';

    const appError = error as ApplicationError;
    return appError.message || '';
  });

  const field = computed(() => {
    if (!error || typeof error !== 'object') return '';

    const appError = error as ApplicationError;
    const details = appError.details as EntitlementErrorDetails | undefined;

    return details?.field || '';
  });

  const errorDetails = computed(() => {
    if (!error || typeof error !== 'object') return {};

    const appError = error as ApplicationError;
    const details = appError.details as EntitlementErrorDetails | undefined;

    return details?.details || {};
  });

  return {
    isUpgradeRequired,
    errorMessage,
    field,
    errorDetails,
  };
}
