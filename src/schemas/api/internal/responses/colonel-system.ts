// src/schemas/api/internal/responses/colonel-system.ts
//
// Per-resource schema surface for the colonel System screen (ticket #33).
// Internal-only; consumed by the Vue admin console.
//
// The System screen is a READ-ONLY status/info read-out over three endpoints
// that ALREADY have frozen response schemas in ./colonel:
//   - GET /api/colonel/system/database → databaseMetricsResponseSchema
//   - GET /api/colonel/system/redis    → redisMetricsResponseSchema
//   - GET /api/colonel/queue           → queueMetricsResponseSchema
//
// Per CONTRACT 3 (the Zod tripwire) those contracts are REUSED, never
// duplicated. This file merely RE-EXPORTS them so the System view imports every
// system contract from one per-resource module and typechecks independently of
// the registry — the schemas themselves live in ./colonel and are untouched.

export {
  databaseMetricsResponseSchema,
  redisMetricsResponseSchema,
  queueMetricsResponseSchema,
} from './colonel';

export type {
  DatabaseMetricsResponse,
  RedisMetricsResponse,
  QueueMetricsResponse,
} from './colonel';
