// src/utils/api.ts
import axios from 'axios';
import { useCsrfStore } from '@/stores/csrfStore';

const api = axios.create();

api.interceptors.request.use((config) => {
  const csrfStore = useCsrfStore();

  // We should only need to pass the CSRF token in via form field
  // or HTTP header and not both. The old way was form field and
  // the new way is header so we'll do this both ways for the time
  // being until we can remove the form field method.
  config.data = config.data || {};
  config.data.shrimp = csrfStore.shrimp;

  config.headers = config.headers || {};
  config.headers['O-Shrimp'] = csrfStore.shrimp;

  return config;
});

api.interceptors.response.use(
  (response) => {
    const csrfStore = useCsrfStore();
    console.debug('[Axios Interceptor] Success response:', {
      url: response.config.url,
      status: response.status,
      hasShrimp: !!response.data?.shrimp,
      shrimp: response.data?.shrimp?.slice(0, 8) + '...' // Log first 8 chars for debugging
    });

    if (response.data?.shrimp) {
      csrfStore.updateShrimp(response.data.shrimp);
      console.debug('[Axios Interceptor] Updated shrimp token after success');
    }
    return response;
  },
  (error) => {
    const csrfStore = useCsrfStore();
    console.debug('[Axios Interceptor] Error response:', {
      url: error.config?.url,
      status: error.response?.status,
      hasShrimp: !!error.response?.data?.shrimp,
      shrimp: error.response?.data?.shrimp?.slice(0, 8) + '...',
      error: error.message
    });

    if (error.response?.data?.shrimp) {
      csrfStore.updateShrimp(error.response.data.shrimp);
      console.debug('[Axios Interceptor] Updated shrimp token after error');
    }
    return Promise.reject(error);
  }
);

export default api;
