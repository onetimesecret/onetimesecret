// services/logging.ts
import type { ApplicationError } from '@/schemas/errors';

export interface LoggingService {
  error(error: ApplicationError): void;
  warn(message: string, context?: Record<string, unknown>): void;
  info(message: string, context?: Record<string, unknown>): void;
}

// services/logging/console.ts
// import type { LoggingService } from './types';
// import type { ApplicationError } from '@/schemas/errors';

export class ConsoleLoggingService implements LoggingService {
  error(error: ApplicationError): void {
    console.error(error.message, error);
  }

  warn(message: string, context?: Record<string, unknown>): void {
    console.warn(message, context);
  }

  info(message: string, context?: Record<string, unknown>): void {
    console.info(message, context);
  }
}

export const loggingService: LoggingService = new ConsoleLoggingService();
