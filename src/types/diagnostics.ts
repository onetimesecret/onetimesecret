// src/types/diagnostics.ts

/**
 * Runtime Diagnostics Configuration Types
 *
 * Bootstrap payload types come from contracts/bootstrap.ts (single source of truth).
 * Sentry SDK types come from shapes for SDK integration.
 *
 * @see src/schemas/contracts/bootstrap.ts for bootstrap payload schema
 * @see src/schemas/shapes/config/diagnostics.ts for Sentry SDK integration
 */

// Bootstrap payload types (what Ruby sends to frontend)
export {
  diagnosticsSchema,
  sentryConfigSchema,
  type DiagnosticsConfig,
  type SentryConfig,
} from '@/schemas/contracts/bootstrap';

// Re-export Sentry types for consumers that need them
export type { Integration, ErrorEvent } from '@sentry/core';
