import { ApiError, handleError } from '@/schemas/api/errors';
import { useNotificationsStore } from '@/stores/notifications';
import { defineStore } from 'pinia';

interface BaseState {
  isLoading: boolean;
  error: ApiError | null;
}

export const createBaseStore = <T extends object>(options: {
  id: string;
  state?: () => T;
}) => {
  return defineStore(options.id, {
    state: () =>
      ({
        isLoading: false,
        error: null,
        ...(options.state ? options.state() : {}),
      }) as T & BaseState,

    actions: {
      handleError(error: unknown): never {
        const notifications = useNotificationsStore();
        const apiError = handleError(error);
        console.error('[Store Error]', {
          code: apiError.code,
          message: apiError.message,
          details: apiError.details,
        });
        this.error = apiError;
        notifications.show(apiError.message, 'error');
        throw apiError;
      },

      async withLoading<R>(operation: () => Promise<R>): Promise<R> {
        this.startLoading();
        try {
          const result = await operation();
          return result;
        } catch (error) {
          this.handleError(error);
          throw error; // Ensure we always return or throw
        } finally {
          this.stopLoading();
        }
      },

      startLoading() {
        this.isLoading = true;
        this.error = null;
      },

      stopLoading() {
        this.isLoading = false;
      },

      clearError() {
        this.error = null;
      },

      resetState() {
        const initialState = options.state?.() || {};
        Object.assign(this, {
          isLoading: false,
          error: null,
          ...initialState,
        });
      },
    },
  });
};
