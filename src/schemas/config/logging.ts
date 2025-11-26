// src/schemas/config/logging.ts

/**
 * Logging Configuration Schema
 *
 * Zod v4 schema for etc/defaults/logging.defaults.yaml
 *
 * Purpose:
 * - Type-safe validation of logging configuration
 * - Runtime validation for YAML parsing
 * - TypeScript type inference for logging config usage
 *
 * Strategic categories for debugging and operational instrumentation:
 *   Auth     - Authentication/authorization flows
 *   Session  - Session lifecycle management
 *   HTTP     - HTTP requests, responses, and middleware
 *   Familia  - Redis operations via Familia ORM
 *   Otto     - Otto framework operations
 *   Rhales   - Rhales template rendering
 *   Sequel   - Database queries and operations
 *   Secret   - Core business value (create/view/burn)
 *   App      - Default fallback for application-level logging
 */

import { z } from 'zod/v4';
import { nullableString } from './shared/primitives';

/**
 * Log level enum
 */
const logLevelSchema = z.enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal']);

/**
 * Output formatter enum
 */
const formatterSchema = z.enum(['color', 'json', 'default']);

/**
 * HTTP capture mode
 */
const httpCaptureSchema = z.enum(['minimal', 'standard', 'debug']);

/**
 * Named logger levels
 * Each category can be configured independently
 */
const loggersSchema = z.object({
  App: logLevelSchema.default('info'),
  Auth: logLevelSchema.default('info'),
  Billing: logLevelSchema.default('info'),
  Boot: logLevelSchema.default('info'),
  Familia: logLevelSchema.default('warn'),
  HTTP: logLevelSchema.default('warn'),
  Otto: logLevelSchema.default('warn'),
  Rhales: logLevelSchema.default('error'),
  Secret: logLevelSchema.default('info'),
  Sequel: logLevelSchema.default('warn'),
  Session: logLevelSchema.default('info'),
}).catchall(logLevelSchema);

/**
 * HTTP request logging configuration
 */
const httpLoggingSchema = z.object({
  enabled: z.boolean().default(true),
  level: nullableString,
  capture: httpCaptureSchema.default('standard'),
  slow_request_ms: z.number().int().positive().default(1000),
  ignore_paths: z.array(z.string()).default([
    '/api/v1/status',
    '/api/v2/status',
    '/api/v3/status',
    '/health',
    '/healthcheck',
    '/favicon.ico',
    '/_vite/*',
    '/assets/*',
    '/dist/*',
  ]),
});

/**
 * Complete logging configuration schema
 *
 * Matches the structure from etc/defaults/logging.defaults.yaml
 */
const loggingConfigSchema = z.object({
  default_level: logLevelSchema.default('info'),
  formatter: formatterSchema.default('color'),
  loggers: loggersSchema.optional(),
  http: httpLoggingSchema.optional(),
});

export type LogLevel = z.infer<typeof logLevelSchema>;
export type Formatter = z.infer<typeof formatterSchema>;
export type HttpCapture = z.infer<typeof httpCaptureSchema>;
export type Loggers = z.infer<typeof loggersSchema>;
export type HttpLogging = z.infer<typeof httpLoggingSchema>;
export type LoggingConfig = z.infer<typeof loggingConfigSchema>;

export {
  loggingConfigSchema,
  logLevelSchema,
  formatterSchema,
  httpCaptureSchema,
  loggersSchema,
  httpLoggingSchema,
};

/**
 * Type guard: Check if logging config is valid
 *
 * @param data - Unknown data to validate
 * @returns True if data matches LoggingConfig schema
 */
export function isLoggingConfig(data: unknown): data is LoggingConfig {
  return loggingConfigSchema.safeParse(data).success;
}
