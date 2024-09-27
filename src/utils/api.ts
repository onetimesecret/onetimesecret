// src/utils/api.ts
import axios from 'axios';
import { useCsrfStore } from '@/stores/csrfStore';

const api = axios.create();

api.interceptors.request.use((config) => {
  const csrfStore = useCsrfStore();
  config.data = config.data || {};
  config.data.shrimp = csrfStore.shrimp;
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
