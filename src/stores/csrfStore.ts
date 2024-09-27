// src/stores/csrfStore.ts
import { defineStore } from 'pinia';

export const useCsrfStore = defineStore('csrf', {
  state: () => ({
    shrimp: window.shrimp || '',
  }),
  actions: {
    updateShrimp(newShrimp: string) {
      this.shrimp = newShrimp;
      window.shrimp = newShrimp;
    },
  },
});
