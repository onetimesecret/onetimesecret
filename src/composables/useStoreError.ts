import { ApiError, handleError as apiHandleError } from '@/schemas/api/errors';
import { useNotificationsStore } from '@/stores/notifications';

export function useStoreError() {
  const notifications = useNotificationsStore();

  return {
    handleError(error: unknown): ApiError {
      // Handle abort errors without showing notification
      if (error instanceof Error && error.name === 'AbortError') {
        console.debug('Request aborted');
        return {
          message: 'Request aborted',
          code: 499, // Client Closed Request
          name: 'AbortError',
        };
      }

      const apiError = apiHandleError(error);
      notifications.show(apiError.message, 'error');
      return apiError;
    },
  };
}
