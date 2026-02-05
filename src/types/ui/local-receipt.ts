// src/types/ui/local-receipt.ts

/**
 * Local receipt types
 *
 * Re-exports from schemas. Schemas are defined in schemas/ui/local-receipt.ts
 * as the single source of truth. Types are derived via z.infer<>.
 *
 * Runtime validation via these schemas is critical because data comes from
 * sessionStorage which could be corrupted, tampered with, or from an older
 * app version.
 */

export {
  guestReceiptRecordSchema,
  guestReceiptsResponseSchema,
  localReceiptSchema,
  localReceiptsArraySchema,
  type GuestReceiptRecord,
  type GuestReceiptsResponse,
  type LocalReceipt,
  type LocalReceiptsArray,
} from '@/schemas/ui/local-receipt';
