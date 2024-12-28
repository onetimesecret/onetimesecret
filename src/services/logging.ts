// services/logging.ts
import type { ApplicationError } from '@/schemas/errors';

export interface LoggingService {
  error(error: ApplicationError): void;
  warn(message: string, context?: Record<string, unknown>): void;
  info(message: string, context?: Record<string, unknown>): void;
}
