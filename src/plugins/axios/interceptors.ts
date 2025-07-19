// src/plugins/axios/interceptors.ts
import type { ApiErrorResponse } from '@/schemas/api';
import { useLanguageStore } from '@/stores';
import { useCsrfStore } from '@/stores/csrfStore';
import type { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from 'axios';

/**
 * CSRF Token Interceptors
 *
 * A comprehensive system for managing CSRF (Cross-Site Request Forgery)
 * tokens, referred to as "shrimp" in this implementation.
 *
 * Key Features:
 * - Automatic token management in headers
 * - Token validation and updates
 * - Detailed debug logging
 * - Error handling with token preservation
 *
 * Flow:
 * 1. Request: Attaches current token to headers
 * 2. Response: Updates token if new one is provided
 * 3. Error: Preserves token updates even in error cases
 */

/**
 * Validates if a given value is a valid shrimp token
 * @param shrimp - The value to validate
 * @returns boolean indicating if the value is a valid string token
 */
const isValidShrimp = (shrimp: unknown): shrimp is string =>
  typeof shrimp === 'string' && shrimp.length > 0;

/**
 * Request interceptor that adds the CSRF token to outgoing requests
 * @param config - Axios request configuration
 * @returns Modified config with CSRF token in headers
 */
export const requestInterceptor = (config: InternalAxiosRequestConfig) => {
  const csrfStore = useCsrfStore();
  const languageStore = useLanguageStore();

  // console.debug('[debug] Request config:', {
  //   url: config.url,
  //   method: config.method,
  //   baseURL: config.baseURL,
  // });

  // Set CSRF token in headers
  config.headers = config.headers || {};
  config.headers['o-shrimp'] = csrfStore.shrimp;
  config.headers['accept-language'] = languageStore.getCurrentLocale;

  return config;
};

/**
 * Response interceptor that handles successful responses and token updates
 * @param response - Axios response object
 * @returns The original response after processing
 */
export const responseInterceptor = (response: AxiosResponse) => {
  const csrfStore = useCsrfStore();
  const responseShrimp = response.data?.shrimp;

  if (isValidShrimp(responseShrimp)) {
    csrfStore.updateShrimp(responseShrimp);
  }

  return response;
};

/**
 * Error interceptor that handles failed requests while preserving token updates
 * @param error - Axios error object
 * @returns Rejected promise with simplified error message
 */
export const errorInterceptor = (error: AxiosError) => {
  const csrfStore = useCsrfStore();
  const responseData = error.response?.data as ApiErrorResponse | undefined;
  const responseShrimp = responseData?.shrimp;

  // console.error('[errorInterceptor] ', {
  //   url: error.config?.url,
  //   method: error.config?.method,
  //   status: error.response?.status,
  //   hasShrimp: responseData?.shrimp ? true : false,
  //   shrimp: createLoggableShrimp(responseShrimp),
  //   error: error.message,
  //   name: error.name,
  // });

  // Update our local shrimp token if new one is provided
  if (isValidShrimp(responseShrimp)) {
    csrfStore.updateShrimp(responseShrimp);
  }

  return Promise.reject(error); // no gate keeping, just pass the error along
};

/**
 * Creates a truncated version of the shrimp token for safe logging
 * @param shrimp - The token to process
 * @returns A truncated version of the token (first 4 chars + "...")
 */
export const createLoggableShrimp = (shrimp: unknown): string => {
  if (!isValidShrimp(shrimp)) {
    return '';
  }
  return `${shrimp.slice(0, 4)}...`;
};
