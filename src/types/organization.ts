// src/types/organization.ts

/**
 * Organization management type definitions
 *
 * Types are derived from Zod schemas in @/schemas/shapes/organizations/organization.
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
} from '@/schemas/shapes/organizations/organization';

/**
 * Runtime constants for organization entitlements
 *
 * These map to STANDALONE_ENTITLEMENTS in the backend (lib/onetime/billing/catalog.rb)
 * Used for feature gating based on plan tier.
 *
 * Note: The Entitlement type is derived from entitlementSchema in schemas.
 */
export const ENTITLEMENTS = {
  // Core
  CREATE_SECRETS: 'create_secrets',
  VIEW_RECEIPT: 'view_receipt',
  HOMEPAGE_SECRETS: 'homepage_secrets',
  INCOMING_SECRETS: 'incoming_secrets',
  NOTIFICATIONS: 'notifications',

  // Infrastructure
  API_ACCESS: 'api_access',
  CUSTOM_DOMAINS: 'custom_domains',
  IP_ACCESS_RULES: 'ip_access_rules',

  // Privacy & Defaults
  CUSTOM_PRIVACY_DEFAULTS: 'custom_privacy_defaults',
  EXTENDED_DEFAULT_EXPIRATION: 'extended_default_expiration',
  CUSTOM_MAIL_SENDER: 'custom_mail_sender',
  FLEXIBLE_FROM_DOMAIN: 'flexible_from_domain',

  // Branding
  CUSTOM_BRANDING: 'custom_branding',
  WORKSPACE_BRANDING: 'workspace_branding',

  // Organization Management
  MANAGE_ORG: 'manage_org',
  MANAGE_ORGS: 'manage_orgs',
  MANAGE_TEAMS: 'manage_teams',
  MANAGE_MEMBERS: 'manage_members',
  MANAGE_SSO: 'manage_sso',

  // Advanced
  AUDIT_LOGS: 'audit_logs',
  CUSTOM_SIGNIN_CONFIG: 'custom_signin_config',
  CUSTOM_SIGNUP_VALIDATION: 'custom_signup_validation',
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
import type { Organization } from '@/schemas/shapes/organizations/organization';

export function getOrganizationLabel(org: Organization): string {
  return org.display_name;
}

/**
 * Invitation status values that have a localized label under
 * `web.organizations.invitations.status.*`. A status outside this set has no
 * label; callers fall back to the raw status string so an unknown/future enum
 * degrades gracefully instead of crashing or rendering blank.
 *
 * Includes `revoked` for completeness even though the invitation contract enum
 * does not currently emit it (a revoked invitation is deleted server-side, so
 * it never surfaces as a status) — keeping the label wired means the mapping
 * stays correct if that ever changes.
 */
export const LOCALIZED_INVITATION_STATUSES: ReadonlySet<string> = new Set([
  INVITATION_STATUSES.PENDING,
  INVITATION_STATUSES.ACCEPTED,
  INVITATION_STATUSES.DECLINED,
  INVITATION_STATUSES.EXPIRED,
  'revoked',
]);

/**
 * Resolve the effective display status for an invitation. A pending invitation
 * past its expiry still reports `pending` from the API, so surface it as
 * `expired` to match the countdown text rendered alongside it.
 *
 * @param status - raw invitation status
 * @param expiresAtSeconds - expiry as a unix timestamp in seconds
 * @param nowMs - current time in milliseconds (injectable for tests)
 */
export function effectiveInvitationStatus(
  status: string,
  expiresAtSeconds: number,
  nowMs: number = Date.now()
): string {
  // Compare in whole seconds so the badge flips in lockstep with the row's
  // countdown (formatTimeRemaining, which floors to seconds) — never showing
  // "expired" while the countdown still reads "expires soon" on a sub-second gap.
  const nowSeconds = Math.floor(nowMs / 1000);
  if (status === INVITATION_STATUSES.PENDING && expiresAtSeconds <= nowSeconds) {
    return INVITATION_STATUSES.EXPIRED;
  }
  return status;
}

/**
 * i18n key for an invitation status label, or `null` when the status has no
 * localized label (the caller should fall back to the raw status value).
 */
export function invitationStatusLabelKey(status: string): string | null {
  return LOCALIZED_INVITATION_STATUSES.has(status)
    ? `web.organizations.invitations.status.${status}`
    : null;
}
