// src/plugins/axios/interceptors.ts
import type { ApiErrorResponse } from '@/schemas/api';
import { useCsrfStore } from '@/stores/csrfStore';
import type { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from 'axios';

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

  console.debug('[debug] Request config:', {
    url: config.url,
    method: config.method,
    baseURL: config.baseURL,
  });

  // Previously, we submitted CSRF token in form data. Now we
  // submit it in headers only.
  config.headers = config.headers || {};
  config.headers['O-Shrimp'] = csrfStore.shrimp;

  return config;
};

export const responseInterceptor = (response: AxiosResponse) => {
  const csrfStore = useCsrfStore();
  const responseShrimp = response.data?.shrimp;
  const shrimpSnippet = createLoggableShrimp(responseShrimp);

  console.debug('[debug] Success response:', {
    url: response.config.url,
    status: response.status,
    hasShrimp: !!responseShrimp,
    shrimp: shrimpSnippet,
  });

  // Update CSRF token if provided in the response data
  if (isValidShrimp(responseShrimp)) {
    csrfStore.updateShrimp(responseShrimp);
    console.debug('[debug] Updated shrimp token after success');
  }

  return response;
};

export const errorInterceptor = (error: AxiosError) => {
  const csrfStore = useCsrfStore();
  const errorData = error.response?.data as ApiErrorResponse;

  console.error('Error response:', {
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
    console.debug('[debug] Updated shrimp token after error');
  }

  // Optionally, attach the server message to the error object
  const serverMessage = errorData.message || error.message;
  return Promise.reject(new Error(serverMessage));
};
