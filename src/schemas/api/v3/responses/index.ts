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

export type { AccountResponse, ApiTokenResponse, CheckAuthResponse, CustomerResponse } from './account';
export type { LoginResponse, CreateAccountResponse, LogoutResponse, ResetPasswordRequestResponse, ResetPasswordResponse } from './auth';
export type { ColonelInfoResponse, ColonelStatsResponse, ColonelUsersResponse, ColonelSecretsResponse, CustomDomainsResponse, ColonelOrganizationsResponse, InvestigateOrganizationResponse, DatabaseMetricsResponse, RedisMetricsResponse, BannedIPsResponse, UsageExportResponse, QueueMetricsResponse, SystemSettingsResponse } from './colonel';
export type { CsrfResponse } from './csrf';
export type { BrandSettingsResponse, CustomDomainDetails, CustomDomainResponse, CustomDomainListResponse, ImagePropsResponse, JurisdictionResponse } from './domains';
export type { FeedbackResponse } from './feedback';
export type { IncomingConfigResponse, IncomingSecretResponse, ValidateRecipientResponse } from './incoming';
export type { OrganizationResponse, OrganizationListResponse, OrganizationDeleteResponse, MemberListResponse, MemberResponse, MemberDeleteResponse } from './organizations';
export type { ReceiptResponse, ReceiptListResponse } from './receipts';
export type { ConcealDataResponse, SecretResponse, SecretListResponse } from './secrets';
export type { SystemStatusResponse, SystemVersionResponse, SupportedLocalesResponse } from './meta';
