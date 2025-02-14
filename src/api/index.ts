import {
  errorInterceptor,
  requestInterceptor,
  responseInterceptor,
} from '@/plugins/axios/interceptors';
import { Locale } from '@/schemas/i18n';
import axios, { type AxiosInstance } from 'axios';

// NOTE: Import createApi directly from '@/api' in new code.

/**
 * BACKWARDS COMPATIBILITY NOTICE:
 * This module provides both a default export and a createApi factory function.
 * - Use the default export for existing code and simple cases
 * - Use createApi() for new code that needs domain configuration
 *
 * The default export will be maintained for backwards compatibility, but new code
 * should prefer using createApi() for better configuration options and flexibility.
 */

/**
 * Configuration options for creating an API instance.
 * Only applicable when using the createApi() factory function.
 */
interface ApiConfig {
  /**
   * Base domain URL for API requests. Supports the following formats:
   * - Domain only (e.g. 'api.example.com')
   * - HTTP URL (will be upgraded to HTTPS)
   * - HTTPS URL (e.g. 'https://api.example.com')
   *
   * @remarks
   * - If no protocol is specified, HTTPS will be automatically added
   * - HTTP protocol will be automatically upgraded to HTTPS
   * - Only HTTPS is supported; other protocols will throw an error
   *
   * @throws {Error} If the URL is invalid or uses an unsupported protocol
   */
  domain?: string;
  /**
   * Locale to use for API requests. This will be sent as the 'Accept-Language' header.
   * If not specified, the user's browser locale will be used by default.
   */
  locale?: Locale;
}

/**
 * Creates a configured Axios instance with CSRF protection and interceptors.
 * This is the recommended way to create new API instances, especially when
 * custom domain configuration is needed.
 *
 * @param config - Configuration options for the API instance
 * @returns An Axios instance configured with the specified options and interceptors
 * @throws {Error} If the provided domain is invalid or uses an unsupported protocol
 *
 * @example
 * ```typescript
 * // Create API instance with various domain formats
 * const api1 = createApi({ domain: 'api.example.com' });         // adds https://
 * const api2 = createApi({ domain: 'http://api.example.com' });  // converts to https://
 * const api3 = createApi({ domain: 'https://api.example.com' }); // already correct
 *
 * // Invalid configurations that will throw errors
 * createApi({ domain: 'ftp://api.example.com' })   // Error: Only HTTPS protocol is supported
 * createApi({ domain: 'not a url' })               // Error: Invalid domain URL
 * ```
 */
const createApi = (config: ApiConfig = {}): AxiosInstance => {
  let baseURL = config.domain?.trim();

  // console.debug('[createApi] Initializing API with config:', config);

  if (baseURL) {
    // If no protocol specified, prepend https://
    if (!baseURL.match(/^[a-zA-Z]+:\/\//)) {
      baseURL = `https://${baseURL}`;
    }

    // If http://, replace with https://
    if (baseURL.startsWith('http://')) {
      baseURL = baseURL.replace('http://', 'https://');
    }

    // Validate that we now have a proper https URL
    try {
      const url = new URL(baseURL);
      if (url.protocol !== 'https:') {
        throw new Error('Only HTTPS protocol is supported');
      }
    } catch (error: unknown) {
      console.error('[createApi] URL validation error:', error);
      if (error instanceof Error) {
        throw new Error(`Invalid domain URL: ${error.message}`);
      } else {
        throw new Error('Invalid domain URL');
      }
    }
  }

  const api = axios.create({
    baseURL,
    withCredentials: true,
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
  });

  // Only set locale if specified. Seems obvious and it is, but it
  // also means we don't mess with the browser's default locale.
  if (config.locale) api.defaults.headers['Accept-Language'] = config.locale;

  api.interceptors.request.use(requestInterceptor);
  api.interceptors.response.use(responseInterceptor, errorInterceptor);

  return api;
};

export { createApi };

/**
 * Default API instance.
 *
 * @deprecated Use createApi() for new code.
 * The default export is kept for compatibility.
 * No new options will be added.
 *
 * @example
 * // Legacy pattern:
 * import api from '@/api';
 * const response = api.get('/items');
 *
 * // Modern pattern:
 * import { createApi } from '@/api';
 * const api = createApi();
 * const response = api.get('/items');
 */
const defaultApi = createApi();
export default defaultApi;
