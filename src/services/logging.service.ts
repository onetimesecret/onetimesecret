// src/services/logging.service.ts

const STARTUP_BANNER = `
┏┓┳┓┏┓┏┳┓┳┳┳┓┏┓
┃┃┃┃┣  ┃ ┃┃┃┃┣
┗┛┛┗┗┛ ┻ ┻┛ ┗┗┛
`;

export interface LoggingService {
  error(error: Error): void;
  warn(message: string, context?: Record<string, unknown>): void;
  info(message: string, context?: Record<string, unknown>): void;
  debug(message: string, context?: Record<string, unknown>): void;
  banner(): void;
}

// services/logging/console.ts
// import type { LoggingService } from './types';
// import type { ApplicationError } from '@/schemas/errors';

export class ConsoleLoggingService implements LoggingService {
  error(error: Error): void {
    console.error(error.message, error);
  }

  warn(message: string, context?: Record<string, unknown>): void {
    console.warn(message, context);
  }

  info(message: string, context?: Record<string, unknown>): void {
    console.info(message, context);
  }

  debug(message: string, context?: Record<string, unknown>): void {
    console.debug(message, context);
  }

  banner(): void {
    console.log(STARTUP_BANNER);
  }
}

export const loggingService: LoggingService = new ConsoleLoggingService();
