// useErrorHandler.ts
import type { ApplicationError, ErrorSeverity } from '@/schemas/errors';
import { classifyError } from '@/schemas/errors/classifier';

export interface ErrorHandlerOptions {
  notify?: (message: string, severity: ErrorSeverity) => void;
  log?: (error: ApplicationError) => void;
  setLoading?: (isLoading: boolean) => void;
}
export function useErrorHandler(options: ErrorHandlerOptions = {}) {
  async function withErrorHandling<T>(operation: () => Promise<T>): Promise<T> {
    try {
      options.setLoading?.(true);
      return await operation();
    } catch (error) {
      const classifiedError = classifyError(error);
      options.log?.(classifiedError);
      if (classifiedError.type === 'human') {
        options.notify?.(classifiedError.message, classifiedError.severity);
      }
      throw classifiedError;
    } finally {
      options.setLoading?.(false);
    }
  }

  return { withErrorHandling };
}
