// src/schemas/api/v2/responses/meta.ts
//
// Re-exports V3 meta response schemas. V2 and V3 meta endpoints
// return identical shapes.

export {
  systemStatusResponseSchema,
  systemVersionResponseSchema,
  supportedLocalesResponseSchema,
} from '../../v3/responses/meta';

export type {
  SystemStatusResponse,
  SystemVersionResponse,
  SupportedLocalesResponse,
} from '../../v3/responses/meta';
