import { ApiError, handleError as apiHandleError } from '@/schemas/api/errors';
import { useNotificationsStore } from '@/stores/notifications';

export function useStoreError() {
  const notifications = useNotificationsStore();

  return {
    handleError(error: unknown): ApiError {
      const apiError = apiHandleError(error);
      notifications.show(apiError.message, 'error');
      return apiError;
    },
  };
}
