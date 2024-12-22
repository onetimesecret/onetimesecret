import { ApiError, handleError } from '@/schemas/api/errors';
import { useNotificationsStore } from '@/stores/notifications';
import { defineStore } from 'pinia';

interface BaseState {
  isLoading: boolean;
  error: ApiError | null;
}

// https://stackoverflow.com/questions/76928581/extending-or-composing-pinia-setup-stores-for-reusable-getters-setters-and-acti
// https://github.com/vuejs/pinia/discussions/901
// https://pinia.vuejs.org/cookbook/composing-stores.html
export const createBaseStore = <T extends object>(options: {
  id: string;
  state?: () => T;
  getters?: Record<string, any>;
  actions?: Record<string, any>;
}) => {
  return defineStore(options.id, {
    state: () =>
      ({
        isLoading: false,
        error: null,
        ...(options.state?.() || {}),
      }) as T & BaseState,

    getters: options.getters,

    actions: {
      handleError(error: unknown) {
        const notifications = useNotificationsStore();
        const apiError = handleError(error);

        console.error('[Store Error]', {
          code: apiError.code,
          message: apiError.message,
          details: apiError.details,
        });

        this.error = apiError;
        notifications.show(apiError.message, 'error');
        return apiError;
      },

      async withLoading<R>(operation: () => Promise<R>): Promise<R | undefined> {
        this.startLoading();
        try {
          return await operation();
        } catch (error) {
          this.handleError(error);
          return undefined;
        } finally {
          this.stopLoading();
        }
      },

      ...(options.actions || {}),
    },
  });
};
