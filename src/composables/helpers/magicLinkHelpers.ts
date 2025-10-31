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
  err: any,
  t: (key: string) => string,
  defaultKey: string
): [string, [string, string] | null] {
  if (err.response?.data) {
    const errorData = err.response.data;
    return [
      errorData.error || t(defaultKey),
      errorData['field-error'] || null
    ];
  }
  return [t('web.auth.magicLink.networkError'), null];
}
