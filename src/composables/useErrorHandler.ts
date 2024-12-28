import { ApiError, handleError as apiHandleError } from '@/schemas/errors/api';
import { useNotificationsStore } from '@/stores/notificationsStore';
import axios from 'axios';
import { ZodError } from 'zod';

type ErrorResult = {
  kind: 'api' | 'validation' | 'network' | 'abort';
  error: ApiError;
  retryable: boolean;
};

export function useErrorHandler() {
  const notifications = useNotificationsStore();

  function classifyError(error: unknown): ErrorResult {
    // Network/Request errors
    if (axios.isAxiosError(error)) {
      const statusCode = error.response?.status;
      return {
        kind: 'network',
        error: {
          message: getAxiosErrorMessage(error),
          code: statusCode ?? 500,
          name: 'NetworkError',
        },
        retryable: statusCode ? isRetryableStatus(statusCode) : true,
      };
    }

    // Abort handling
    if (error instanceof Error && error.name === 'AbortError') {
      return {
        kind: 'abort',
        error: {
          message: 'Request aborted',
          code: 499,
          name: 'AbortError',
        },
        retryable: true,
      };
    }

    // Validation errors
    if (error instanceof ZodError) {
      return {
        kind: 'validation',
        error: formatZodError(error),
        retryable: false,
      };
    }

    // Default API error handling
    return {
      kind: 'api',
      error: apiHandleError(error),
      retryable: false,
    };
  }

  return {
    handleError(error: unknown): ApiError {
      const result = classifyError(error);

      // Don't notify on aborted requests
      if (result.kind !== 'abort') {
        notifications.show(result.error.message, 'error');
      }

      // Log for debugging with appropriate context
      console.error(`[${result.kind}] Error:`, {
        message: result.error.message,
        code: result.error.code,
        retryable: result.retryable,
        originalError: error,
      });

      return result.error;
    },
  };
}

// Helper functions
function getAxiosErrorMessage(error: axios.AxiosError): string {
  if (error.response) {
    return error.response.status === 404
      ? 'Secret not found or already viewed'
      : (error.response.data?.message ?? 'An error occurred while fetching the secret');
  }
  return error.request ? 'No response received from server' : 'Network error occurred';
}

function formatZodError(error: ZodError): ApiError {
  const uniqueFields = new Set(error.errors.map((err) => err.path[err.path.length - 1]));

  return {
    message:
      Array.from(uniqueFields)
        .map((field) => `Invalid field(s): ${String(field)}`)
        .join(', ') || 'Invalid data received from server',
    code: 422,
    name: 'ValidationError',
    debug: error.errors,
  };
}

function isRetryableStatus(status: number): boolean {
  return [408, 429, 500, 502, 503, 504].includes(status);
}
