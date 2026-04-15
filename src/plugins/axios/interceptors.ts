// src/plugins/axios/interceptors.ts

import {
  scrubSensitiveStrings,
  scrubUrlWithPatterns,
} from '@/plugins/core/enableDiagnostics';
import { useLanguageStore } from '@/shared/stores';
import { useCsrfStore } from '@/shared/stores/csrfStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { addBreadcrumb } from '@sentry/vue';
import type { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from 'axios';

import { scrubSensitiveStrings, scrubUrlWithPatterns } from '../core/enableDiagnostics';

/**
 * CSRF Token Interceptors
 *
 * Manages CSRF (Cross-Site Request Forgery) tokens using Rack::Protection.
 *
 * Key Features:
 * - Automatic token management in X-CSRF-Token header
 * - Token validation and updates from server responses
 * - Error handling with token preservation
 *
 * Flow:
 * 1. Request: Attaches current token to X-CSRF-Token header
 * 2. Response: Updates token from X-CSRF-Token response header
 * 3. Error: Preserves token updates even in error cases
 *
 * The token is stored in session[:csrf] by Rack::Protection::AuthenticityToken middleware.
 */

/**
 * Validates if a given value is a valid shrimp token
 * @param shrimp - The value to validate
 * @returns boolean indicating if the value is a valid string token
 */
const isValidShrimp = (shrimp: unknown): shrimp is string =>
  typeof shrimp === 'string' && shrimp.length > 0;

/**
 * Domain Context Override header name.
 * Used for persona-based testing in development mode.
 */
const DOMAIN_CONTEXT_HEADER = 'O-Domain-Context';
const DOMAIN_CONTEXT_STORAGE_KEY = 'domainContext';

/**
 * Gets the domain context override from sessionStorage.
 * @returns The domain context value or null if not set
 */
const getDomainContext = (): string | null => {
  try {
    return sessionStorage.getItem(DOMAIN_CONTEXT_STORAGE_KEY);
  } catch {
    // sessionStorage may not be available (SSR, private browsing, etc.)
    return null;
  }
};

/**
 * Request interceptor that adds the CSRF token to outgoing requests
 * @param config - Axios request configuration
 * @returns Modified config with CSRF token in headers
 */
export const requestInterceptor = (config: InternalAxiosRequestConfig) => {
  config.headers = config.headers || {};

  // Access all Pinia stores in a single try/catch block.
  // Pinia throws if called before app.use(pinia) during bootstrap.
  try {
    const csrfStore = useCsrfStore();
    const languageStore = useLanguageStore();
    const organizationStore = useOrganizationStore();

    // Set CSRF token (Rack::Protection::JsonCsrf expects X-CSRF-Token)
    config.headers['X-CSRF-Token'] = csrfStore.shrimp;
    config.headers['Accept-Language'] = languageStore.getCurrentLocale;

    // Sync frontend org selection to backend on every request
    if (organizationStore.currentOrganization?.objid) {
      config.headers['O-Organization-ID'] = organizationStore.currentOrganization.objid;
    }
  } catch {
    // Pinia not yet active during app bootstrap — request proceeds without store headers
  }

  // Add domain context override header if set (development feature)
  const domainContext = getDomainContext();
  if (domainContext) {
    config.headers[DOMAIN_CONTEXT_HEADER] = domainContext;
  }

  // For FormData uploads, delete Content-Type so Axios sets it with the boundary
  if (config.data instanceof FormData) {
    delete config.headers['Content-Type'];
  }

  return config;
};

/**
 * Response interceptor that handles successful responses and token updates
 * @param response - Axios response object
 * @returns The original response after processing
 */
export const responseInterceptor = (response: AxiosResponse) => {
  const csrfStore = useCsrfStore();
  // Read CSRF token from response header (industry standard)
  const responseShrimp = response.headers['x-csrf-token'];

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
  // Read CSRF token from response header even in error cases
  const responseShrimp = error.response?.headers['x-csrf-token'];

  // Add Sentry breadcrumb for API debugging (#2965)
  // Scrub sensitive data from URL and error message before sending
  const method = error.config?.method?.toUpperCase() ?? 'UNKNOWN';
  const url = error.config?.url ? scrubUrlWithPatterns(error.config.url) : 'unknown';
  addBreadcrumb({
    type: 'http',
    category: 'axios',
    message: `${method} ${url}`,
    data: {
      status_code: error.response?.status,
      reason: scrubSensitiveStrings(error.message),
    },
    level: 'error',
  });

  // Update our local shrimp token if new one is provided
  if (isValidShrimp(responseShrimp)) {
    csrfStore.updateShrimp(responseShrimp);
  }

  // Add Sentry breadcrumb for API error debugging
  const scrubbedUrl = scrubUrlWithPatterns(error.config?.url ?? '');
  const method = error.config?.method?.toUpperCase() || 'HTTP';
  addBreadcrumb({
    type: 'http',
    category: 'http.client',
    level: 'error',
    message: `${method} ${scrubbedUrl}`,
    data: {
      url: scrubbedUrl,
      method,
      status_code: error.response?.status,
      reason: scrubSensitiveStrings(error.message),
    },
  });

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
