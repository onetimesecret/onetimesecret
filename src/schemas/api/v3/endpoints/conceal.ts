// src/schemas/api/v3/endpoints/conceal.ts
//
// V3 re-exports the V2 conceal endpoint schemas.
// V2 owns these definitions — V3 inherits the business logic.
// If V3 needs to diverge (e.g., additional fields), extend here.

export {
  concealReceiptSchema,
  concealDataSchema,
  type ConcealData,
  type ConcealReceipt,
} from '@/schemas/api/v2/endpoints/secrets';
