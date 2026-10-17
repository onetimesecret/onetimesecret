// src/services/logging.service.ts

const STARTUP_BANNER = `
┏┓┳┓┏┓┏┳┓┳┳┳┓┏┓
┃┃┃┃┣  ┃ ┃┃┃┃┣
┗┛┛┗┗┛ ┻ ┻┛ ┗┗┛
`;

export type LogLevel = 'debug' | 'info' | 'warn' | 'error' | 'silent';

const LEVEL_RANK: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
  silent: 4,
};

/**
 * The lowest level that reaches the console. Debug and info are for a
 * developer's own browser: in the test suite they surround every passing
 * spec with output nobody reads, and in production they run in every
 * visitor's browser. Tests that assert on a debug line spy on
 * `loggingService.debug`, which records the call whatever the level.
 *
 * Outside Vite (the schema check CLI bundles this module and runs it under
 * plain node) there is no import.meta.env, and the level is warn.
 */
export function defaultLogLevel(
  env: { MODE: string; DEV: boolean } | undefined = import.meta.env
): LogLevel {
  if (!env || env.MODE === 'test') return 'warn';
  return env.DEV ? 'debug' : 'warn';
}

export interface LoggingService {
  error(error: Error): void;
  warn(message: string, context?: Record<string, unknown>): void;
  info(message: string, context?: Record<string, unknown>): void;
  debug(message: string, context?: Record<string, unknown>): void;
  banner(): void;
  getLevel(): LogLevel;
  setLevel(level: LogLevel): void;
}

// services/logging/console.ts
// import type { LoggingService } from './types';
// import type { ApplicationError } from '@/schemas/errors';

export class ConsoleLoggingService implements LoggingService {
  private level: LogLevel;

  constructor(level: LogLevel = defaultLogLevel()) {
    this.level = level;
  }

  getLevel(): LogLevel {
    return this.level;
  }

  setLevel(level: LogLevel): void {
    this.level = level;
  }

  private enabled(level: Exclude<LogLevel, 'silent'>): boolean {
    return LEVEL_RANK[level] >= LEVEL_RANK[this.level];
  }

  error(error: Error): void {
    if (this.enabled('error')) console.error(error.message, error);
  }

  warn(message: string, context?: Record<string, unknown>): void {
    if (this.enabled('warn')) console.warn(...withContext(message, context));
  }

  info(message: string, context?: Record<string, unknown>): void {
    if (this.enabled('info')) console.info(...withContext(message, context));
  }

  debug(message: string, context?: Record<string, unknown>): void {
    if (this.enabled('debug')) console.debug(...withContext(message, context));
  }

  // The banner is not a log message: it prints whatever the level.
  banner(): void {
    console.log(STARTUP_BANNER);
  }
}

// Without a context the console would print a trailing `undefined`.
function withContext(message: string, context?: Record<string, unknown>): unknown[] {
  return context === undefined ? [message] : [message, context];
}

export const loggingService: LoggingService = new ConsoleLoggingService();
