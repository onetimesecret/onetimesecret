import { ApiError, handleError as apiHandleError } from '@/schemas/api/errors';
import { useNotificationsStore } from '@/stores/notificationsStore';
import axios from 'axios'; // not for making requests
import { ZodError } from 'zod';

export function useErrorHandler() {
  const notifications = useNotificationsStore();

  return {
    handleError(error: unknown): ApiError {
      console.error(
        '[debug] Handling error type:',
        error?.constructor?.name ?? typeof error
      );

      let errorMessage = 'An unexpected error occurred';
      let statusCode = null;

      if (axios.isAxiosError(error)) {
        if (error.response) {
          statusCode = error.response.status;
          errorMessage =
            statusCode === 404
              ? 'Secret not found or already viewed'
              : error.response.data?.message ||
                'An error occurred while fetching the secret';
        } else if (error.request) {
          errorMessage = 'No response received from server';
        }
      }

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
