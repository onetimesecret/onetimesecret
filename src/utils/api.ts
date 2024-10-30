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

api.interceptors.response.use((response) => {
  const csrfStore = useCsrfStore();
  if (response.data && response.data.shrimp) {
    csrfStore.updateShrimp(response.data.shrimp);
  }
  return response;
});

export default api;
