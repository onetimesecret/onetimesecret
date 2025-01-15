// src/schemas/models/plan.ts
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * Plan options schema matching Ruby model
 */
export const planOptionsSchema = z.object({
  ttl: transforms.fromString.number,
  size: transforms.fromString.number,
  api: transforms.fromString.boolean,
  name: z.string(),
  email: transforms.fromString.boolean.optional(),
  custom_domains: transforms.fromString.boolean.optional(),
  dark_mode: transforms.fromString.boolean.optional(),
  cname: transforms.fromString.boolean.optional(),
  private: transforms.fromString.boolean.optional(),
});

export type PlanOptions = z.infer<typeof planOptionsSchema>;

/**
 * Plan schema for customer plans
 */
export const planSchema = z.object({
  identifier: z.string(),
  planid: z.string(),
  price: transforms.fromString.number,
  discount: transforms.fromString.number,
  options: planOptionsSchema,
});

export type Plan = z.infer<typeof planSchema>;
