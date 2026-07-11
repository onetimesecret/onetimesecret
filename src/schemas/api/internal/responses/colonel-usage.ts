// src/schemas/api/internal/responses/colonel-usage.ts
//
// Per-resource schema surface for the colonel Usage screen (ticket #33).
// Internal-only; consumed by the Vue admin console.
//
// The Usage screen is a READ-ONLY metrics read-out over one endpoint that
// ALREADY has a frozen response schema in ./colonel:
//   - GET /api/colonel/usage/export → usageExportResponseSchema
//
// Per CONTRACT 3 (the Zod tripwire) that contract is REUSED, never duplicated.
// This file RE-EXPORTS it so the Usage view imports from one per-resource module
// and typechecks independently of the registry — the schema itself lives in
// ./colonel and is untouched.

export { usageExportResponseSchema } from './colonel';
export type { UsageExportResponse } from './colonel';
