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
  created_at: string;
  updated_at: string;
}

/**
 * Zod schemas for validation
 */

export const organizationSchema = z.object({
  id: z.string(),
  display_name: z.string().min(1).max(100),
  description: z.string().max(500).optional(),
  created_at: z.union([z.string(), z.number()]).transform(val => String(val)),
  updated_at: z.union([z.string(), z.number()]).transform(val => String(val)),
});

/**
 * Request payload schemas
 */

export const createOrganizationPayloadSchema = z.object({
  display_name: z.string().min(1, 'Organization name is required').max(100, 'Organization name is too long'),
  description: z.string().max(500, 'Description is too long').optional(),
});

export const updateOrganizationPayloadSchema = z.object({
  display_name: z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
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
