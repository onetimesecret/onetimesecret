// src/schemas/ui/index.ts

/**
 * UI Schemas
 *
 * Zod schemas and derived types for UI components and utilities.
 * Provides runtime validation for data from external sources
 * (sessionStorage, API responses) and consistent type definitions
 * for component props.
 */

// Form utilities (TypeScript types that work with Zod schemas)
export type { FormSubmissionOptions } from './forms';

// Layout schemas and types
export {
  improvedLayoutPropsSchema,
  layoutDisplaySchema,
  layoutPropsSchema,
  logoConfigSchema,
  type ImprovedLayoutProps,
  type LayoutDisplay,
  type LayoutProps,
  type LogoConfig,
} from './layouts';

// Local receipt schemas and types (sessionStorage data)
export {
  guestReceiptRecordSchema,
  guestReceiptsResponseSchema,
  localReceiptSchema,
  localReceiptsArraySchema,
  type GuestReceiptRecord,
  type GuestReceiptsResponse,
  type LocalReceipt,
  type LocalReceiptsArray,
} from './local-receipt';

// Notification types
export type { NotificationSeverity } from './notifications';
