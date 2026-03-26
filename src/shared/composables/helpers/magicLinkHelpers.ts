// src/shared/composables/helpers/magicLinkHelpers.ts

/**
 * Helper functions for Magic Link composable
 */

/**
 * Handles error extraction from response
 *
 * @param err - Error object
 * @param t - Translation function
 * @param defaultKey - Default translation key
 * @returns Error message and field error tuple
 */
export function extractError(
  err: unknown,
  t: (key: string) => string,
  defaultKey: string
): [string, [string, string] | null] {
  const response = (err as { response?: { data?: Record<string, unknown> } })?.response;
  if (response?.data) {
    const errorData = response.data;
    return [
      (typeof errorData.error === 'string' ? errorData.error : null) || t(defaultKey),
      (Array.isArray(errorData['field-error']) ? errorData['field-error'] as [string, string] : null)
    ];
  }
  return [t('web.auth.magicLink.networkError'), null];
}
