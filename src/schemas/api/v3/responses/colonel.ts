// src/schemas/api/v3/responses/colonel.ts
//
// Colonel (admin) response schemas. These use z.object({}) as the record
// type intentionally — admin endpoints return all data in details, not record.
// Re-exported from V2 since admin payloads are internal and don't need
// JSON-native variants for public API documentation.

export {
  colonelInfoResponseSchema,
  colonelStatsResponseSchema,
  colonelUsersResponseSchema,
  colonelSecretsResponseSchema,
  colonelCustomDomainsResponseSchema,
  colonelOrganizationsResponseSchema,
  investigateOrganizationResponseSchema,
  databaseMetricsResponseSchema,
  redisMetricsResponseSchema,
  bannedIPsResponseSchema,
  usageExportResponseSchema,
  queueMetricsResponseSchema,
  systemSettingsResponseSchema,
  type ColonelInfoResponse,
  type ColonelStatsResponse,
  type ColonelUsersResponse,
  type ColonelSecretsResponse,
  type CustomDomainsResponse,
  type ColonelOrganizationsResponse,
  type InvestigateOrganizationResponse,
  type DatabaseMetricsResponse,
  type RedisMetricsResponse,
  type BannedIPsResponse,
  type UsageExportResponse,
  type QueueMetricsResponse,
  type SystemSettingsResponse,
} from '@/schemas/api/v2/responses/colonel';
