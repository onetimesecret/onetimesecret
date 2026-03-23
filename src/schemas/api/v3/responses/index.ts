// src/schemas/api/v3/responses/index.ts
//
// V3 response schema barrel exports.
//
// V3 schemas use JSON-native input types (booleans, numbers, strings) that
// match what the V3 API sends over the wire. Timestamp fields use
// transforms.fromNumber.toDate to convert Unix epoch seconds into Date
// objects at parse time. This works with io:"input" in z.toJSONSchema()
// so OpenAPI still documents the wire type (number), not the output (Date).
//
// Unlike V2 schemas, V3 does NOT use z.preprocess() or transforms.fromString.*
// because the V3 backend sends properly typed JSON (not Redis string encodings).

// ─────────────────────────────────────────────────────────────────────────────
// Registry re-export (single source of truth for schema lookup)
// ─────────────────────────────────────────────────────────────────────────────

export { responseSchemas, type ResponseTypes } from './registry';

// ─────────────────────────────────────────────────────────────────────────────
// Type re-exports from domain modules (for tree-shaking friendly imports)
// ─────────────────────────────────────────────────────────────────────────────

export type {
  CreateAccountResponse,
  LoginResponse,
  LogoutResponse,
  ResetPasswordRequestResponse,
  ResetPasswordResponse,
} from './auth';
export type {
  BrandSettingsResponse,
  CustomDomainDetails,
  CustomDomainListResponse,
  CustomDomainResponse,
  ImagePropsResponse,
  JurisdictionResponse,
} from './domains';
export type {
  AccountResponse,
  ApiTokenResponse,
  CheckAuthResponse,
  CustomerResponse,
} from './account';
export type { FeedbackResponse } from './feedback';
export type {
  IncomingConfigResponse,
  IncomingSecretResponse,
  ValidateRecipientResponse,
} from './incoming';
export type { SupportedLocalesResponse, SystemStatusResponse, SystemVersionResponse } from './meta';
export type { ReceiptListResponse, ReceiptResponse } from './receipts';
export type { ConcealDataResponse, SecretListResponse, SecretResponse } from './secrets';
