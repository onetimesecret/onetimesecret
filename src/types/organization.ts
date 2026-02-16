// src/types/organization.ts

/**
 * Organization management type definitions
 *
 * Types are derived from Zod schemas in @/schemas/models/organization.
 * This file re-exports them and provides runtime constants for convenience.
 */

// Re-export all schemas and types from canonical location
export {
  // Schemas
  createInvitationPayloadSchema,
  createOrganizationPayloadSchema,
  entitlementSchema,
  invitationStatusSchema,
  organizationInvitationSchema,
  organizationLimitsSchema,
  organizationMemberSchema,
  organizationRoleSchema,
  organizationSchema,
  updateMemberRolePayloadSchema,
  updateOrganizationPayloadSchema,
  // Types (derived from schemas via z.infer<>)
  type CreateInvitationPayload,
  type CreateOrganizationPayload,
  type Entitlement,
  type InvitationStatus,
  type Organization,
  type OrganizationInvitation,
  type OrganizationLimits,
  type OrganizationMember,
  type OrganizationRole,
  type UpdateMemberRolePayload,
  type UpdateOrganizationPayload,
} from '@/schemas/models/organization';

/**
 * Runtime constants for organization entitlements
 *
 * These map to STANDALONE_ENTITLEMENTS in the backend (lib/onetime/billing/catalog.rb)
 * Used for feature gating based on plan tier.
 *
 * Note: The Entitlement type is derived from entitlementSchema in schemas.
 */
export const ENTITLEMENTS = {
  // Infrastructure
  API_ACCESS: 'api_access',
  CUSTOM_DOMAINS: 'custom_domains',

  // Privacy & Defaults
  CUSTOM_PRIVACY_DEFAULTS: 'custom_privacy_defaults',
  EXTENDED_DEFAULT_EXPIRATION: 'extended_default_expiration',
  CUSTOM_MAIL_DEFAULTS: 'custom_mail_defaults',

  // Branding
  CUSTOM_BRANDING: 'custom_branding',
  HOMEPAGE_SECRETS: 'homepage_secrets',

  // Secret Features
  INCOMING_SECRETS: 'incoming_secrets',

  // Organization Management
  MANAGE_ORGS: 'manage_orgs',
  MANAGE_TEAMS: 'manage_teams',
  MANAGE_MEMBERS: 'manage_members',

  // Advanced
  AUDIT_LOGS: 'audit_logs',
} as const;

/**
 * Runtime constants for organization roles
 */
export const ORGANIZATION_ROLES = {
  OWNER: 'owner',
  ADMIN: 'admin',
  MEMBER: 'member',
} as const;

/**
 * Runtime constants for invitation statuses
 */
export const INVITATION_STATUSES = {
  PENDING: 'pending',
  ACCEPTED: 'accepted',
  DECLINED: 'declined',
  EXPIRED: 'expired',
} as const;

/**
 * Display helpers
 */
import type { Organization } from '@/schemas/models/organization';

export function getOrganizationLabel(org: Organization): string {
  return org.display_name;
}
