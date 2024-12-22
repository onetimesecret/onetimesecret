// src/plugins/axios/interceptors.ts
import type { ApiErrorResponse } from '@/schemas/api';
import { useCsrfStore } from '@/stores/csrfStore';
import type { AxiosError, InternalAxiosRequestConfig } from 'axios';

/**
 * CSRF Token Interceptors
 *
 * These interceptors handle CSRF token management across API requests:
 *
 * 1. Request Handling:
 *    - Adds CSRF token to both form data and headers
 *    - Maintains backward compatibility during transition
 *
 * 2. Response Processing:
 *    - Updates CSRF token from successful responses
 *    - Handles token updates in error responses
 *    - Maintains token synchronization
 *
 * 3. Error Management:
 *    - Preserves error context
 *    - Updates tokens even on failures
 *    - Provides clean error messages
 */

const isValidShrimp = (shrimp: unknown): shrimp is string => {
  return typeof shrimp === 'string' && shrimp.length > 0;
};

const createLoggableShrimp = (shrimp: unknown): string => {
  if (!isValidShrimp(shrimp)) {
    return '';
  }
  return `${shrimp.slice(0, 8)}...`;
};

export const requestInterceptor = (config: InternalAxiosRequestConfig) => {
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
};

export const responseInterceptor = (response: any) => {
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
};

export const errorInterceptor = (error: AxiosError) => {
  const csrfStore = useCsrfStore();
  const errorData = error.response?.data as ApiErrorResponse;

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
};
