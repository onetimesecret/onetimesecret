// src/schemas/contracts/config/logging.ts

/**
 * Logging Configuration Schema
 *
 * Zod v4 schema for etc/defaults/logging.defaults.yaml
 *
 * Per contracts convention, this schema describes field names and types only.
 * Per-logger defaults, the HTTP slow-request threshold, and the ignored-path
 * list live in `shapes/config/logging.ts`.
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

import { z } from 'zod';
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
  App: logLevelSchema.optional(),
  Auth: logLevelSchema.optional(),
  Billing: logLevelSchema.optional(),
  Boot: logLevelSchema.optional(),
  Familia: logLevelSchema.optional(),
  HTTP: logLevelSchema.optional(),
  Otto: logLevelSchema.optional(),
  Rhales: logLevelSchema.optional(),
  Secret: logLevelSchema.optional(),
  Sequel: logLevelSchema.optional(),
  Session: logLevelSchema.optional(),
}).catchall(logLevelSchema);

/**
 * HTTP request logging configuration
 */
const httpLoggingSchema = z.object({
  enabled: z.boolean().optional(),
  level: nullableString,
  capture: httpCaptureSchema.optional(),
  slow_request_ms: z.number().optional(),
  ignore_paths: z.array(z.string()).optional(),
  // Opt-in allowlist of request param/header names allowed to appear in
  // :debug capture mode or in error-report context. Empty by default.
  allowed_error_fields: z.array(z.string()).optional(),
});

/**
 * Complete logging configuration schema
 *
 * Matches the structure from etc/defaults/logging.defaults.yaml
 */
const loggingConfigSchema = z.object({
  default_level: logLevelSchema.optional(),
  formatter: formatterSchema.optional(),
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
