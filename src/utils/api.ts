import type { ApiErrorResponse } from '@/schemas/api';
import { useCsrfStore } from '@/stores/csrfStore';
import axios, { AxiosError, AxiosInstance } from 'axios';

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

  console.debug('[createApi] Initializing API with config:', config);

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
    // Add more default configuration if needed
    withCredentials: true, // Important for cross-origin requests with cookies
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
  });

  api.interceptors.request.use(
    (config) => {
      const csrfStore = useCsrfStore();

      console.debug('[Axios Interceptor] Request config:', {
        url: config.url,
        method: config.method,
        baseURL: config.baseURL,
      });

      // We should only need to pass the CSRF token in via form field
      // or HTTP header and not both. The old way was form field and
      // the new way is header so we'll do this both ways for the time
      // being until we can remove the form field method.
      config.data = config.data || {};
      config.data.shrimp = csrfStore.shrimp;

      config.headers = config.headers || {};
      config.headers['O-Shrimp'] = csrfStore.shrimp;

      return config;
    },
    (error) => {
      console.error('[Axios Interceptor] Request error:', error);
      return Promise.reject(error);
    }
  );

  api.interceptors.response.use(
    (response) => {
      const csrfStore = useCsrfStore();
      const responseShrimp = response.data?.shrimp;
      const shrimpSnippet = createLoggableShrimp(responseShrimp);

      console.debug('[Axios Interceptor] Success response:', {
        url: response.config.url,
        status: response.status,
        hasShrimp: !!responseShrimp,
        shrimp: shrimpSnippet,
      });

      // Update CSRF token if provided in the response data
      if (isValidShrimp(responseShrimp)) {
        csrfStore.updateShrimp(responseShrimp);
        console.debug('[Axios Interceptor] Updated shrimp token after success');
      }

      return response;
    },
    (error: AxiosError) => {
      const csrfStore = useCsrfStore();
      const errorData = error.response?.data as ApiErrorResponse;

      // Existing logging for debugging
      console.error('[Axios Interceptor] Error response:', {
        url: error.config?.url,
        status: error.response?.status,
        hasShrimp: !!errorData.shrimp,
        shrimp: errorData.shrimp?.slice(0, 8) + '...',
        error: error.message,
        errorDetails: error,
      });

      // Update CSRF token if provided in the error response
      if (errorData.shrimp) {
        csrfStore.updateShrimp(errorData.shrimp);
        console.debug('[Axios Interceptor] Updated shrimp token after error');
      }

      // Optionally, attach the server message to the error object
      const serverMessage = errorData.message || error.message;
      return Promise.reject(new Error(serverMessage));
    }
  );

  return api;
};

const isValidShrimp = (shrimp: unknown): shrimp is string => {
  return typeof shrimp === 'string' && shrimp.length > 0;
};

const createLoggableShrimp = (shrimp: unknown): string => {
  if (!isValidShrimp(shrimp)) {
    return '';
  }
  return `${shrimp.slice(0, 8)}...`;
};

/**
 * Default API instance without a custom domain.
 *
 * @deprecated While still supported for backwards compatibility, new code should
 * use createApi() instead. This default export will be maintained but won't
 * receive new configuration options.
 *
 * @example
 * ```typescript
 * // Legacy usage (still supported)
 * import api from '@/utils/api';
 * const response = await api.get('/users');
 *
 * // Preferred modern usage which supports an optional domain
 * // and custom configuration.
 * import { createApi } from '@/utils/api';
 * const api = createApi();
 * const response = await api.get('/users');
 * ```
 */
const defaultApi = createApi();

export { createApi };
export default defaultApi;
