import {
  TechnicalError,
  handleError as handleTechnicalError,
} from '@/schemas/errors/api';
import { DomainError, isUserActionable } from '@/schemas/errors/domain';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { storeToRefs } from 'pinia';

interface ErrorContext {
  source?: string;
  action?: string;
  retry?: () => Promise<void>;
}

export function useErrorHandler() {
  const notifications = useNotificationsStore();
  const { isLoading } = storeToRefs(notifications);

  function handleError(
    error: unknown,
    context?: ErrorContext
  ): TechnicalError | DomainError {
    const processedError = handleTechnicalError(error);

    // Don't show notifications if we're already showing a loading state
    if (!isLoading.value) {
      notifications.show(processedError.userMessage, 'error');
    }

    // Log error with context for debugging
    console.error('[Error]', {
      name: processedError.name,
      message: processedError.message,
      userMessage: processedError.userMessage,
      code: processedError.code,
      retryable: processedError.retryable,
      context,
      details: processedError.details,
    });

    return processedError;
  }

  /**
   * Wraps an async operation with error handling
   */
  async function withErrorHandling<T>(
    operation: () => Promise<T>,
    context?: ErrorContext
  ): Promise<T | undefined> {
    try {
      return await operation();
    } catch (error) {
      handleError(error, context);
      return undefined;
    }
  }

  return {
    handleError,
    withErrorHandling,
    isUserActionable,
  };
}
