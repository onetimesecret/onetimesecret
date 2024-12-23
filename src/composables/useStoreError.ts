import { ApiError, handleError as apiHandleError } from '@/schemas/api/errors';
import { useNotificationsStore } from '@/stores/notifications';
import { ZodError } from 'zod';

export function useStoreError() {
  const notifications = useNotificationsStore();

  return {
    handleError(error: unknown): ApiError {
      console.debug(
        '[debug] Handling error type:',
        error?.constructor?.name ?? typeof error
      );

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
        const uniqueFields = new Set(
          error.errors.map((err) => err.path[err.path.length - 1])
        );

        const userMessage = Array.from(uniqueFields)
          .map((field) => `Invalid field(s): ${String(field)}`)
          .join(', ');

        return {
          message: userMessage || 'Invalid data received from server',
          code: 422,
          name: 'ValidationError',
          // Keep raw details for debugging but don't show in UI
          debug: error.errors,
        };
      }

      const apiError = apiHandleError(error);
      notifications.show(apiError.message, 'error');
      return apiError;
    },
  };
}
