// src/schemas/api/v2/responses/colonel.ts
//
// Response schemas for colonel (admin) endpoints.

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  systemSettingsDetailsSchema,
  colonelInfoDetailsSchema,
  colonelStatsDetailsSchema,
  colonelUsersDetailsSchema,
  colonelSecretsDetailsSchema,
  databaseMetricsDetailsSchema,
  redisMetricsDetailsSchema,
  bannedIPsDetailsSchema,
  usageExportDetailsSchema,
  colonelCustomDomainsDetailsSchema,
  colonelOrganizationsDetailsSchema,
  investigateOrganizationResultSchema,
  queueMetricsDetailsSchema,
} from '@/schemas/api/account/responses/colonel';
import { z } from 'zod';

export const colonelInfoResponseSchema = createApiResponseSchema(z.object({}), colonelInfoDetailsSchema);
export const colonelStatsResponseSchema = createApiResponseSchema(z.object({}), colonelStatsDetailsSchema);
export const colonelUsersResponseSchema = createApiResponseSchema(z.object({}), colonelUsersDetailsSchema);
export const colonelSecretsResponseSchema = createApiResponseSchema(z.object({}), colonelSecretsDetailsSchema);
export const colonelCustomDomainsResponseSchema = createApiResponseSchema(z.object({}), colonelCustomDomainsDetailsSchema);
export const colonelOrganizationsResponseSchema = createApiResponseSchema(z.object({}), colonelOrganizationsDetailsSchema);
export const investigateOrganizationResponseSchema = createApiResponseSchema(investigateOrganizationResultSchema);
export const databaseMetricsResponseSchema = createApiResponseSchema(z.object({}), databaseMetricsDetailsSchema);
export const redisMetricsResponseSchema = createApiResponseSchema(z.object({}), redisMetricsDetailsSchema);
export const bannedIPsResponseSchema = createApiResponseSchema(z.object({}), bannedIPsDetailsSchema);
export const usageExportResponseSchema = createApiResponseSchema(z.object({}), usageExportDetailsSchema);
export const queueMetricsResponseSchema = createApiResponseSchema(z.object({}), queueMetricsDetailsSchema);
export const systemSettingsResponseSchema = createApiResponseSchema(z.object({}), systemSettingsDetailsSchema);

export type ColonelInfoResponse = z.infer<typeof colonelInfoResponseSchema>;
export type ColonelStatsResponse = z.infer<typeof colonelStatsResponseSchema>;
export type ColonelUsersResponse = z.infer<typeof colonelUsersResponseSchema>;
export type ColonelSecretsResponse = z.infer<typeof colonelSecretsResponseSchema>;
export type CustomDomainsResponse = z.infer<typeof colonelCustomDomainsResponseSchema>;
export type ColonelOrganizationsResponse = z.infer<typeof colonelOrganizationsResponseSchema>;
export type InvestigateOrganizationResponse = z.infer<typeof investigateOrganizationResponseSchema>;
export type DatabaseMetricsResponse = z.infer<typeof databaseMetricsResponseSchema>;
export type RedisMetricsResponse = z.infer<typeof redisMetricsResponseSchema>;
export type BannedIPsResponse = z.infer<typeof bannedIPsResponseSchema>;
export type UsageExportResponse = z.infer<typeof usageExportResponseSchema>;
export type QueueMetricsResponse = z.infer<typeof queueMetricsResponseSchema>;
export type SystemSettingsResponse = z.infer<typeof systemSettingsResponseSchema>;
