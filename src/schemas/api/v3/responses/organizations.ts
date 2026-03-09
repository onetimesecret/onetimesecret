// src/schemas/api/v3/responses/organizations.ts
//
// V3 JSON wire-format schemas for organization and member endpoints.
// Timestamps use transforms.fromNumber.toDate so that .parse() returns
// Date objects for the frontend while io:"input" still documents them
// as numbers in OpenAPI.

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

/** Organization record with all IDs and timestamps as plain strings/numbers. */
const organizationRecord = z.object({
  id: z.string(),
  extid: z.string(),
  display_name: z.string(),
  description: z.string().nullish(),
  contact_email: z.string().nullish(),
  billing_email: z.string().nullish(),
  is_default: z.boolean(),
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
  owner_extid: z.string().nullish(),
  member_count: z.number().int().min(0).nullish(),
  current_user_role: z.enum(organizationRoles).nullish(),
  planid: z.string().nullish(),
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
