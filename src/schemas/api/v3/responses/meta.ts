// src/schemas/api/v3/responses/meta.ts
//
// Re-exports V2 meta response schemas. V2 and V3 meta endpoints
// return identical shapes.

export {
  supportedLocalesResponseSchema,
  systemStatusResponseSchema,
  systemVersionResponseSchema,
} from '../../v2/responses/meta';

export type {
  SupportedLocalesResponse,
  SystemStatusResponse,
  SystemVersionResponse,
} from '../../v2/responses/meta';
