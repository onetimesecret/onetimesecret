// src/schemas/shapes/config/logging.ts

/**
 * Logging Configuration Shape
 *
 * Adds runtime defaults on top of the type-only logging contract — per-logger
 * level defaults, HTTP request logging defaults, and the slow-request
 * threshold. The `slow_request_ms` default is the one Ruby actually relies on
 * via `request_logger.rb`, so this shape doubles as the source of truth.
 *
 * @see src/schemas/contracts/config/logging.ts
 */

import { z } from 'zod';
import { nullableString } from '@/schemas/contracts/config/shared/primitives';

export {
  loggingConfigSchema,
  logLevelSchema,
  formatterSchema,
  httpCaptureSchema,
  loggersSchema,
  httpLoggingSchema,
  isLoggingConfig,
} from '@/schemas/contracts/config/logging';

export type {
  LoggingConfig,
  LogLevel,
  Formatter,
  HttpCapture,
  Loggers,
  HttpLogging,
} from '@/schemas/contracts/config/logging';

const logLevelShape = z.enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal']);

const formatterShape = z.enum(['color', 'json', 'default']);

const httpCaptureShape = z.enum(['minimal', 'standard', 'debug']);

const loggersShape = z.object({
  App: logLevelShape.default('info'),
  Auth: logLevelShape.default('info'),
  Billing: logLevelShape.default('info'),
  Boot: logLevelShape.default('info'),
  Familia: logLevelShape.default('warn'),
  HTTP: logLevelShape.default('warn'),
  Otto: logLevelShape.default('warn'),
  Rhales: logLevelShape.default('error'),
  Secret: logLevelShape.default('info'),
  Sequel: logLevelShape.default('warn'),
  Session: logLevelShape.default('info'),
}).catchall(logLevelShape);

const httpLoggingShape = z.object({
  enabled: z.boolean().default(true),
  level: nullableString,
  capture: httpCaptureShape.default('standard'),
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

const loggingConfigShape = z.object({
  default_level: logLevelShape.default('info'),
  formatter: formatterShape.default('color'),
  loggers: loggersShape.optional(),
  http: httpLoggingShape.optional(),
});

export {
  loggingConfigShape,
  logLevelShape,
  formatterShape,
  httpCaptureShape,
  loggersShape,
  httpLoggingShape,
};
