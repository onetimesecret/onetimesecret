// src/schemas/api/v2/responses/domains.ts
//
// Response schemas for custom domain, jurisdiction, brand, and image endpoints.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import {
  customDomainDetailsSchema,
  customDomainSchema,
  jurisdictionDetailsSchema,
  jurisdictionSchema,
} from '@/schemas/models';
import { brandSettingschema, imagePropsSchema } from '@/schemas/models/domain/brand';
import { z } from 'zod';

export const brandSettingsResponseSchema = createApiResponseSchema(brandSettingschema);
export const customDomainResponseSchema = createApiResponseSchema(customDomainSchema, customDomainDetailsSchema);
export const customDomainListResponseSchema = createApiListResponseSchema(customDomainSchema, customDomainDetailsSchema);
export const imagePropsResponseSchema = createApiResponseSchema(imagePropsSchema);
export const jurisdictionResponseSchema = createApiResponseSchema(jurisdictionSchema, jurisdictionDetailsSchema);

export type BrandSettingsResponse = z.infer<typeof brandSettingsResponseSchema>;
export type CustomDomainResponse = z.infer<typeof customDomainResponseSchema>;
export type CustomDomainListResponse = z.infer<typeof customDomainListResponseSchema>;
export type ImagePropsResponse = z.infer<typeof imagePropsResponseSchema>;
export type JurisdictionResponse = z.infer<typeof jurisdictionResponseSchema>;
