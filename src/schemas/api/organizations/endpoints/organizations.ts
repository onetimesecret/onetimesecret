/**
 * Organizations API endpoint schemas
 * Defines request/response schemas for organization management endpoints
 */

import { organizationSchema } from '@/types/organization';
import { z } from 'zod';

/**
 * Single organization response
 * POST /api/organizations
 * GET /api/organizations/:orgid
 * PUT /api/organizations/:orgid
 */
export const organizationResponseSchema = z.object({
  record: organizationSchema,
});

export type OrganizationResponse = z.infer<typeof organizationResponseSchema>;

/**
 * Organizations list response
 * GET /api/organizations
 */
export const organizationsResponseSchema = z.object({
  records: z.array(organizationSchema),
  count: z.number().int().min(0),
});

export type OrganizationsResponse = z.infer<typeof organizationsResponseSchema>;

/**
 * Delete response
 * DELETE /api/organizations/:orgid
 */
export const deleteResponseSchema = z.object({
  success: z.boolean(),
  message: z.string().optional(),
});

export type DeleteResponse = z.infer<typeof deleteResponseSchema>;
