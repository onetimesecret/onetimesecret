// useErrorHandler.ts
import type { ApplicationError, ErrorSeverity } from '@/schemas/errors';

export interface ErrorHandlerOptions {
  notify?: (message: string, severity: ErrorSeverity) => void;
  log?: (error: ApplicationError) => void;
}

export function useErrorHandler(options: ErrorHandlerOptions = {}) {
  async function withErrorHandling<T>(operation: () => Promise<T>): Promise<T> {
    try {
      return await operation();
    } catch (error) {
      const classifiedError = classifyError(error);

      options.log?.(classifiedError);
      options.notify?.(classifiedError.message, classifiedError.severity);

      throw classifiedError;
    }
  }

  return { withErrorHandling };
}
