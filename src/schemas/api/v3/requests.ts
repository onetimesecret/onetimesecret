import { brandSettingschema } from '@/schemas/models/domain/brand';
import { z } from 'zod';
import { concealPayloadSchema, generatePayloadSchema } from './payloads/index';

export const updateDomainBrandRequestSchema = z.object({
  brand: brandSettingschema.partial(),
});

export type UpdateDomainBrandRequest = z.infer<typeof updateDomainBrandRequestSchema>;

export const createDomainRequestSchema = z.object({
  domain: z
    .string()
    .min(3)
    .regex(/^[a-zA-Z0-9][a-zA-Z0-9-_.]+[a-zA-Z0-9]$/),
});

export type CreateDomainRequest = z.infer<typeof createDomainRequestSchema>;

export const concealRequestSchema = z.object({
  secret: concealPayloadSchema,
});
export const generateRequestSchema = z.object({
  secret: generatePayloadSchema,
});

export type ConcealRequest = z.infer<typeof concealRequestSchema>;
export type GenerateRequest = z.infer<typeof generateRequestSchema>;

export interface ExceptionReport {
  message: string;
  type: string;
  stack: string;
  url: string;
  line: number;
  column: number;
  environment: string;
  release: string;
}
