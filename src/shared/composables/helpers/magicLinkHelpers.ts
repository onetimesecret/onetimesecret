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

/**
 * True for the 403 Rack::Protection::AuthenticityToken answers when the CSRF
 * token is missing or stale: a text/plain "Forbidden" with no JSON body. A 403
 * the application itself returns (Rodauth's `already_logged_in`, for one)
 * carries a JSON `error` string and is not a CSRF failure.
 *
 * @param err - Error object
 * @returns Whether the request was refused by the CSRF middleware
 */
export function isCsrfRejection(err: unknown): boolean {
  const response = (err as { response?: { status?: number; data?: unknown } })?.response;
  if (response?.status !== 403) return false;
  const data = response.data;
  const explained =
    typeof data === 'object' &&
    data !== null &&
    typeof (data as Record<string, unknown>).error === 'string';
  return !explained;
}
