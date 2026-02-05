// src/types/diagnostics.ts

/**
 * Runtime Diagnostics Configuration Types
 *
 * Re-exports from the schema definition. The schema provides both validation
 * and type inference for Sentry configuration passed from Ruby backend to
 * Vue frontend.
 *
 * @see src/schemas/models/diagnostics.ts for the authoritative schema
 */

export {
  diagnosticsConfigSchema,
  sentryConfigSchema,
  type DiagnosticsConfig,
  type SentryConfig,
} from '@/schemas/models/diagnostics';

// Re-export Sentry types for consumers that need them
export type { Integration, ErrorEvent } from '@sentry/core';
