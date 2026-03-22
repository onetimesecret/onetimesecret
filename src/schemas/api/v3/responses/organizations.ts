// src/schemas/api/v3/responses/organizations.ts
//
// V3 API response schemas for organization and member endpoints.
//
// Architecture: contract → shapes → api responses
// - organizationRecord from shapes/v3/organization extends organizationCanonical
// - Response schemas extend the shape with API-specific fields (entitlements, limits, etc.)
//
// Response-specific fields not in the canonical contract:
// - member_count, current_user_role: computed at request time
// - entitlements, limits, domain_count: billing/plan data
// - billing_email: response-only alias

import { organizationRecord as baseOrganizationRecord } from '@/schemas/shapes/v3/organization';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Shared enums
// ─────────────────────────────────────────────────────────────────────────────

const organizationRoles = ['owner', 'admin', 'member'] as const;

const entitlements = [
  'api_access', 'custom_domains', 'custom_privacy_defaults',
  'extended_default_expiration', 'custom_mail_defaults', 'custom_branding',
  'incoming_secrets', 'manage_orgs', 'manage_teams', 'manage_members',
  'audit_logs', 'create_secrets', 'view_receipt', 'homepage_secrets',
] as const;

// ─────────────────────────────────────────────────────────────────────────────
// Record schemas
// ─────────────────────────────────────────────────────────────────────────────

const organizationLimits = z.object({
  teams: z.number().optional(),
  members_per_team: z.number().optional(),
  custom_domains: z.number().optional(),
});

/**
 * V3 organization response record.
 *
 * Extends the V3 organization shape with response-specific computed/billing fields.
 * Uses canonical field names from contract (identifier, owner_id).
 */
const organizationRecord = baseOrganizationRecord.extend({
  // Response-only computed fields
  member_count: z.number().int().min(0).nullish(),
  current_user_role: z.enum(organizationRoles).nullish(),

  // Billing/plan fields (not in canonical contract)
  billing_email: z.string().nullish(),
  entitlements: z.array(z.enum(entitlements)).nullish(),
  limits: organizationLimits.nullish(),
  domain_count: z.number().int().min(0).nullish(),
});

/** Organization member record. */
const memberRecord = z.object({
  extid: z.string(),
  email: z.string(),
  role: z.enum(organizationRoles),
  joined_at: transforms.fromNumber.toDate,
  is_owner: z.boolean(),
  is_current_user: z.boolean(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Response schemas (these don't use the standard envelope — they have their
// own shapes defined in the organizations module)
// ─────────────────────────────────────────────────────────────────────────────

export const organizationResponseSchema = z.object({
  record: organizationRecord,
});

export const organizationsResponseSchema = z.object({
  records: z.array(organizationRecord),
  count: z.number().int().min(0),
});

export const orgDeleteResponseSchema = z.object({
  user_id: z.string(),
  deleted: z.boolean(),
  id: z.string(),
});

export const membersResponseSchema = z.object({
  records: z.array(memberRecord),
  count: z.number().int().min(0),
});

export const memberResponseSchema = z.object({
  record: memberRecord,
});

export const memberDeleteResponseSchema = z.object({
  deleted: z.boolean(),
  member_extid: z.string(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type OrganizationResponse = z.infer<typeof organizationResponseSchema>;
export type OrganizationListResponse = z.infer<typeof organizationsResponseSchema>;
export type OrganizationDeleteResponse = z.infer<typeof orgDeleteResponseSchema>;
export type MemberListResponse = z.infer<typeof membersResponseSchema>;
export type MemberResponse = z.infer<typeof memberResponseSchema>;
export type MemberDeleteResponse = z.infer<typeof memberDeleteResponseSchema>;
