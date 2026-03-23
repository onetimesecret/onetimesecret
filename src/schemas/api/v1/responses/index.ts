// src/schemas/api/v1/responses/index.ts
//
// V1 response schema barrel exports.

// ─────────────────────────────────────────────────────────────────────────────
// Registry re-export (single source of truth for schema lookup)
// ─────────────────────────────────────────────────────────────────────────────

export {
  responseSchemas,
  v1ResponseSchemas,
  v1StatusResponseSchema,
  type V1StatusResponse,
  type ResponseTypes,
} from './registry';

// ─────────────────────────────────────────────────────────────────────────────
// Schema re-exports from domain modules
// ─────────────────────────────────────────────────────────────────────────────

export {
  v1ReceiptResponseSchema,
  v1ReceiptListResponseSchema,
  v1SecretRevealResponseSchema,
  v1BurnSecretResponseSchema,
} from './secrets';

export type {
  V1ReceiptResponse,
  V1ReceiptListResponse,
  V1SecretRevealResponse,
  V1BurnSecretResponse,
} from './secrets';
