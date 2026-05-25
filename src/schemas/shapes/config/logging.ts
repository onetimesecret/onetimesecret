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

import {
  loggingConfigSchema,
  logLevelSchema,
  formatterSchema,
  httpCaptureSchema,
  loggersSchema,
  httpLoggingSchema,
  isLoggingConfig,
} from '@/schemas/contracts/config/logging';
import { augment, type AugmentTree } from '@/schemas/utils/augment';

export {
  loggingConfigSchema,
  logLevelSchema,
  formatterSchema,
  httpCaptureSchema,
  loggersSchema,
  httpLoggingSchema,
  isLoggingConfig,
};

export type {
  LoggingConfig,
  LogLevel,
  Formatter,
  HttpCapture,
  Loggers,
  HttpLogging,
} from '@/schemas/contracts/config/logging';

const logLevelShape = logLevelSchema;
const formatterShape = formatterSchema;
const httpCaptureShape = httpCaptureSchema;

const loggersTree: AugmentTree = {
  App: (l) => l.default('info'),
  Auth: (l) => l.default('info'),
  Billing: (l) => l.default('info'),
  Boot: (l) => l.default('info'),
  Familia: (l) => l.default('warn'),
  HTTP: (l) => l.default('warn'),
  Otto: (l) => l.default('warn'),
  Rhales: (l) => l.default('error'),
  Secret: (l) => l.default('info'),
  Sequel: (l) => l.default('warn'),
  Session: (l) => l.default('info'),
};

const httpLoggingTree: AugmentTree = {
  enabled: (b) => b.default(true),
  capture: (e) => e.default('standard'),
  slow_request_ms: (n) => n.int().positive().default(1000),
  ignore_paths: (a) =>
    a.default([
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
};

const loggersShape = augment(loggersSchema, loggersTree);
const httpLoggingShape = augment(httpLoggingSchema, httpLoggingTree);

const loggingConfigShape = augment(loggingConfigSchema, {
  default_level: (l) => l.default('info'),
  formatter: (f) => f.default('color'),
  loggers: loggersTree,
  http: httpLoggingTree,
});

export {
  loggingConfigShape,
  logLevelShape,
  formatterShape,
  httpCaptureShape,
  loggersShape,
  httpLoggingShape,
};
