/**
 * Organization management type definitions
 * Used across organization components, stores, and views
 */

import { z } from 'zod';

/**
 * Organization interface
 */
export interface Organization {
  id: string;
  display_name: string;
  description?: string;
  contact_email?: string;
  is_default: boolean;
  created_at: Date;
  updated_at: Date;
}

/**
 * Zod schemas for validation
 */

export const organizationSchema = z.object({
  id: z.string(),
  display_name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
  contact_email: z.string().email().optional(),
  is_default: z.boolean(),
  created_at: z.number().transform(val => new Date(val * 1000)),
  updated_at: z.number().transform(val => new Date(val * 1000)),
});

/**
 * Request payload schemas
 */

export const createOrganizationPayloadSchema = z.object({
  display_name: z.string().min(1, 'Organization name is required').max(100, 'Organization name is too long'),
  description: z.string().max(500, 'Description is too long').optional(),
  contact_email: z.string().email('Valid email required').optional(),
});

export const updateOrganizationPayloadSchema = z.object({
  display_name: z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
  contact_email: z.string().email().optional(),
});

/**
 * Type exports from schemas
 */
export type CreateOrganizationPayload = z.infer<typeof createOrganizationPayloadSchema>;
export type UpdateOrganizationPayload = z.infer<typeof updateOrganizationPayloadSchema>;

/**
 * Display helpers
 */

export function getOrganizationLabel(org: Organization): string {
  return org.display_name;
}
