import { ApiError, handleError as apiHandleError } from '@/schemas/api/errors';
import { useNotificationsStore } from '@/stores/notifications';
import { ZodError } from 'zod';

export function useStoreError() {
  const notifications = useNotificationsStore();

  return {
    handleError(error: unknown): ApiError {
       console.debug('Handling error type:', error?.constructor?.name ?? typeof error);

      // Handle abort errors without showing notification
      if (error instanceof Error && error.name === 'AbortError') {
        console.debug('Request aborted');
        return {
          message: 'Request aborted',
          code: 499, // Client Closed Request
          name: 'AbortError',
        };
      }

      // Handle Zod validation errors
      if (error instanceof ZodError) {
        console.error('Validation error:', error.errors);
        return {
          message: 'Invalid data received from server',
          code: 422, // Unprocessable Entity
          name: 'ValidationError',
          details: error.errors,
        };
      }

      const apiError = apiHandleError(error);
      notifications.show(apiError.message, 'error');
      return apiError;
    },
  };
}
