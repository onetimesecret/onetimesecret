// stores/windowStore.ts
import { ErrorHandlerOptions, useErrorHandler } from '@/composables/useErrorHandler';
import { OnetimeWindow } from '@/types/declarations/window';
import { createApi } from '@/utils';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';

export interface StoreState extends Partial<OnetimeWindow> {
  isLoading: boolean;
  _initialized: boolean;
}

function mapAllWindowProperties(window: OnetimeWindow) {
  return { ...window };
}

export const useWindowStore = defineStore('window', {
  state: (): StoreState => ({
    isLoading: false,
    _initialized: false,
    authenticated: false,
    email: '',
    baseuri: '',
    cust: null,
    is_paid: false,
    domains_enabled: false,
    plans_enabled: false,
    // Include other properties as needed
  }),

  getters: {
    // Add getters here
    // For example:
    isAuthenticated(state) {
      return state.authenticated;
    },
  },

  actions: {
    _api: null as AxiosInstance | null,
    _errorHandler: null as ReturnType<typeof useErrorHandler> | null,

    _ensureErrorHandler() {
      if (!this._errorHandler) this.setupErrorHandler();
    },

    // Allow passing options during initialization
    setupErrorHandler(
      api: AxiosInstance = createApi(),
      options: ErrorHandlerOptions = {}
    ) {
      this._api = api;
      this._errorHandler = useErrorHandler({
        setLoading: (isLoading) => {
          this.isLoading = isLoading;
        },
        notify: options.notify, // Allow UI layer to handle notifications if provided
        log: options.log, // Allow custom logging if provided
      });
    },

    reset() {
      this.$reset();
      this._initialized = false; // Explicitly reset initialization flag
    },

    // Initialize store state from window properties
    init(windowObj: Partial<OnetimeWindow> = window as OnetimeWindow) {
      if (this._initialized) return;

      this._ensureErrorHandler();

      // Explicitly use the values from windowObj without fallbacks
      const windowData = {
        authenticated: windowObj.authenticated,
        email: windowObj.email,
        baseuri: windowObj.baseuri,
        cust: windowObj.cust,
        is_paid: windowObj.is_paid,
        domains_enabled: windowObj.domains_enabled,
        plans_enabled: windowObj.plans_enabled,
      };

      // Remove the nullish coalescing since we want to use the exact values
      this.$patch(windowData);
      this._initialized = true;
    },

    // Fetch fresh window data from server
    async fetch() {
      this._ensureErrorHandler();

      return await this._errorHandler!.withErrorHandling(async () => {
        const { data } = await this._api!.get('/api/v2/window'); // Assume this endpoint exists

        // Update store state
        this.$patch(mapAllWindowProperties(data));
      });
    },
  },
});
