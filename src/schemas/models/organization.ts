// src/schemas/models/organization.ts

/**
 * Organization Zod schemas for validation
 *
 * Validates API responses and request payloads for organization management.
 * Types are defined in @/types/organization - schemas here provide runtime validation.
 */

import { z } from 'zod';

import { lenientExtIdSchema, lenientObjIdSchema } from '@/types/identifiers';
import type { Entitlement } from '@/types/organization';

/**
 * Organization schema
 *
 * Validates organization data from API responses.
 * Uses lenient ID schemas during migration phase.
 */
export const organizationSchema = z.object({
  // Use lenient schemas during migration - accepts any string but brands the output
  id: lenientObjIdSchema,
  extid: lenientExtIdSchema,
  display_name: z.string().min(1).max(100),
  description: z.string().max(500).nullish(),
  contact_email: z.email().nullish(),
  is_default: z.preprocess((v) => v ?? false, z.boolean()),
  created_at: z.number().transform((val) => new Date(val * 1000)),
  updated_at: z.number().transform((val) => new Date(val * 1000)),
  owner_extid: lenientExtIdSchema.nullish(),
  member_count: z.number().int().min(0).nullish(),
  current_user_role: z.enum(['owner', 'admin', 'member']).nullish(),
  planid: z.string().nullish(),
  entitlements: z.array(z.string() as z.ZodType<Entitlement>).nullish(),
  limits: z
    .object({
      teams: z.number().optional(),
      members_per_team: z.number().optional(),
      custom_domains: z.number().optional(),
    })
    .nullish(),
  domain_count: z.number().int().min(0).nullish(),
});

/**
 * Create organization request payload schema
 */
export const createOrganizationPayloadSchema = z.object({
  display_name: z
    .string()
    .min(1, 'Organization name is required')
    .max(100, 'Organization name is too long'),
  description: z.string().max(500, 'Description is too long').optional(),
  contact_email: z.email('Valid email required').optional(),
});

/**
 * Update organization request payload schema
 */
export const updateOrganizationPayloadSchema = z.object({
  display_name: z.string().min(1).max(100).optional(),
  description: z.string().max(500).optional(),
  billing_email: z.email('Valid email required').optional(),
});

/**
 * Organization invitation schema
 *
 * Validates invitation data from API responses.
 */
export const organizationInvitationSchema = z.object({
  id: lenientObjIdSchema,
  organization_id: lenientExtIdSchema, // Backend returns org.extid
  email: z.email(),
  role: z.enum(['member', 'admin']),
  status: z.enum(['pending', 'accepted', 'declined', 'expired']),
  invited_by: lenientObjIdSchema,
  invited_at: z.number(),
  expires_at: z.number(),
  resend_count: z.number().int().min(0),
  token: z.string().optional(),
});

/**
 * Create invitation request payload schema
 */
export const createInvitationPayloadSchema = z.object({
  email: z.email('Valid email required'),
  role: z.enum(['member', 'admin']),
});

/**
 * Organization member schema
 *
 * Validates response from GET /api/organizations/:extid/members
 */
export const organizationMemberSchema = z.object({
  extid: lenientExtIdSchema,
  email: z.email(),
  role: z.enum(['owner', 'admin', 'member']),
  joined_at: z.number(),
  is_owner: z.boolean(),
  is_current_user: z.boolean(),
});

/**
 * Update member role request payload schema
 */
export const updateMemberRolePayloadSchema = z.object({
  role: z.enum(['admin', 'member']),
});
